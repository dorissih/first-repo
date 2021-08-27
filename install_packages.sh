#!/bin/bash

# This shell script installs packages on a remote instance through ssh
# ssh -i ~/terraform_project.pem ubuntu@hostname

# cd to home
cd ~/

# Install aws cli
sudo apt install unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install



# Install kubectl
# You must use a kubectl version that is within one minor version difference of your cluster. 
# For example, a v1.22 client can communicate with v1.21, v1.22, and v1.23 control planes. Using the latest version of kubectl helps avoid unforeseen issues.

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Validate the binary (optional)
# Download the kubectl checksum file:
curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"


# Command substitution
echo "Checking for file validity..."
file_validity="`echo "$(<kubectl.sha256) kubectl" | sha256sum --check `"            # kubectl: OK
echo $file_validity


if [ "$file_validity" == "kubectl: OK" ]
then
    # If valid, then install
	echo "I will install kubectl"
    echo "sleeping for 3mins"
    sleep 180
    echo "Done sleeping"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    echo "Installation success!"
else
	echo "Error: I will not install kubectl"
fi













# #!/bin/bash
# echo "Hello Bash Scripting!"

# filevalidity="Say Something"


# # if [ 6 -eq 6 ]
# if [ "$filevalidity" == "Say Somethin" ]
# then
# 	echo "I will say something"
# else
# 	echo "I will not say anything"
# fi

