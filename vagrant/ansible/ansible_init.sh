#!/usr/bin/env bash

sudo apt-get update
sudo apt-get -y upgrade
sudo apt-get -y dist-upgrade
sudo apt-get -y install software-properties-common python3
sudo apt-add-repository --yes --update ppa:ansible/ansible
sudo apt-get -y install ansible