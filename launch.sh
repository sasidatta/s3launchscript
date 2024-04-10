#!/bin/bash
 
# Check if argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <cluster_name>"
    ECS_CLUSTER_NAME="demo"
else
    ECS_CLUSTER_NAME="$1"
fi

# Enable password authentication for SSH
# First, uncomment PasswordAuthentication if it's commented out, regardless of its value
sudo sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Next, ensure PasswordAuthentication is set to yes
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

for conf_file in /etc/ssh/sshd_config.d/*.conf; do
  sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' "$conf_file"
done

# Restart SSH service
systemctl restart ssh

# Update system
apt-get update
apt-get upgrade -y

# Setup AWS CLI default region (replace 'ap-south-1' with your region)
aws configure set default.region us-east-1

USERNAME="jenkins"
# Fetch parameters from AWS SSM
#JENKINS_PASSWORD=$(aws ssm get-parameter --name "JenkinsUserPassword" --with-decryption --query "Parameter.Value" --output text)
JENKINS_PASSWORD="jenk!n$"
SHELL="/bin/bash"  # Specify the desired shell here

# Create the user with the specified shell
useradd -m -s "$SHELL" "$USERNAME" 

# Create a Jenkins user and add it to the sudo and Docker groups
#sudo useradd -m -s /bin/bash jenkins
sudo usermod -aG sudo $USERNAME
sudo usermod -aG docker $USERNAME

# Set the password
echo "$USERNAME:$JENKINS_PASSWORD" | chpasswd

# Install Docker
sudo apt-get install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker

# Add the default user to the Docker group
sudo usermod -aG docker $USERNAME

# Install Node.js and npm
curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install Nginx
sudo apt-get install -y nginx
sudo systemctl start nginx
sudo systemctl enable nginx


# Install and configure the Amazon ECS Agent
mkdir -p /var/log/ecs /etc/ecs /var/lib/ecs/data
touch /etc/ecs/ecs.config
# Set up necessary rules to enable IAM roles for tasks
sysctl -w net.ipv4.conf.all.route_localnet=1
iptables -t nat -A PREROUTING -p tcp -d 169.254.170.2 --dport 80 -j DNAT --to-destination 127.0.0.1:51679
iptables -t nat -A OUTPUT -d 169.254.170.2 -p tcp -m tcp --dport 80 -j REDIRECT --to-ports 51679


# Define the configurations
configs=(
    "ECS_DATADIR=/data"
    "ECS_ENABLE_TASK_IAM_ROLE=true"
    "ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true"
    "ECS_LOGFILE=/log/ecs-agent.log"
    "ECS_AVAILABLE_LOGGING_DRIVERS=[\"json-file\",\"awslogs\"]"
    "ECS_LOGLEVEL=info"
    "ECS_CLUSTER=$ECS_CLUSTER_NAME"
)

# Path to the ECS config file
ecs_config_file="/etc/ecs/ecs.config"

# Loop through configurations and add them to the ECS config file
for config in "${configs[@]}"; do
    echo "$config" | sudo tee -a "$ecs_config_file" >/dev/null
done

echo "Configurations added to $ecs_config_file"



# Download ecs agent from relative zone# Set AWS region from GitHub Workflows environment variable
AWS_REGION="$AWS_REGION"

# Check if AWS_REGION is set, if not set default to us-east-1
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-1"
fi

docker run --name ecs-agent \
    --detach=true \
    --restart=on-failure:10 \
    --volume=/var/run/docker.sock:/var/run/docker.sock \
    --volume=/var/log/ecs:/log \
    --volume=/var/lib/ecs/data:/data \
    --net=host \
    --env-file=/etc/ecs/ecs.config \
    --env=ECS_LOGFILE=/log/ecs-agent.log \
    --env=ECS_DATADIR=/data/ \
    --env=ECS_ENABLE_TASK_IAM_ROLE=true \
    --env=ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true \
    amazon/amazon-ecs-agent:latest

sudo reboot
