FROM ubuntu:latest

RUN apt-get update && apt-get install -y -qq \
      curl build-essential flex g++ git-svn libcairo2-dev libglib2.0-dev \
      libcups2-dev libgtkglext1-dev git-core libglu1-mesa-dev libnspr4-dev \
      libnss3-dev libgnome-keyring-dev libasound2-dev gperf bison libpci-dev \
      libkrb5-dev libgtk-3-dev libxss-dev python libpulse-dev ca-certificates \
      default-jre
