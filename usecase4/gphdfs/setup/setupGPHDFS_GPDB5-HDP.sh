#!/bin/bash
set -e
[[ ${DEBUG} == true ]] && set -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Including configurations
. "${DIR}"/../config.sh

###############################################################################
function InstallJDK()
{
  echo "Install Java on each Greenplum Database segment host"
  # Fix this issue "Rpmdb checksum is invalid: dCDPT(pkg checksums)"
  gpssh -e -v -f ${GPDB_HOSTS} -u root rpm --rebuilddb
  #;  yum clean all
  if rpm -qa | grep wget  2>&1 > /dev/null; then
    gpssh -e -v -f ${GPDB_HOSTS} -u root yum -y install wget
  fi

  if rpm -qa | grep wget  2>&1 > /dev/null; then
    gpssh -e -v -f ${GPDB_HOSTS} -u root yum -y install java-1.8.0-openjdk
  fi
  # sudo yum install java-1.8.0-openjdk
  # sudo yum install java-1.7.0-openjdk
  # sudo yum install java-1.6.0-openjdk

  echo "Update the gpadmin user’s .bash_profile file on each segment host to include this $JAVA_HOME setting"

  export JRE_HOME=$(pwd /usr/lib/jvm/java-1.8.0-openjdk-*/jre_)
  echo "JRE_HOME : ${JRE_HOME}"
  echo "Add Java home to gpadmin bashrc"
  gpssh -e -v -f ${GPDB_HOSTS} -u gpadmin "echo 'export JAVA_HOME=/usr/lib/jvm/jre-openjdk/' >> /home/gpadmin/.bash_profile"
  gpssh -e -v -f ${GPDB_HOSTS} -u gpadmin "echo 'export JAVA_HOME=/usr/lib/jvm/jre-openjdk/' >> /home/gpadmin/.bashrc"
}
###############################################################################
function isInstalled() {
    if rpm -q $1 &> /dev/null; then
        echo 'installed';
        return 1;
    else
        echo 'not installed';
        return 0;
    fi
}

################################################################################
function SetupHDP()
{
  echo "Setup Hortonworks"
  sudo yum -y  remove hadoop* 
  sudo wget -nv http://public-repo-1.hortonworks.com/HDP/centos7/2.x/updates/2.6.3.0/hdp.repo -O /etc/yum.repos.d/hdp.repo
  sudo yum -y --skip-broken install hadoop* openssl
  gpssh -e -v -f ${GPDB_HOSTS} -u gpadmin "gpconfig -c gp_hadoop_target_version -v 'hdp'"

  gpssh -e -v -f ${GPDB_HOSTS} -u gpadmin "echo 'export HADOOP_HOME=/usr/hdp/current/hadoop-client' >> /home/gpadmin/.bashrc"

  if [ "$(whoami)" == "gpadmin" ]; then
    gpconfig -c gp_hadoop_target_version -v  'hdp'
    gpconfig -c gp_hadoop_home -v /usr/hdp/current/hadoop-client/
    gpstop -r -a
    gpconfig -s gp_hadoop_target_version
    gpconfig -s gp_hadoop_home
  elif [ "$(whoami)" == "root" ]; then
    runuser -l gpadmin -c "gpconfig -c gp_hadoop_target_version -v  'hdp'"
    runuser -l gpadmin -c "gpconfig -c gp_hadoop_home -v /usr/hdp/current/hadoop-client/"
    runuser -l gpadmin -c "gpstop -r -a"
    runuser -l gpadmin -c "gpconfig -s gp_hadoop_target_version "
    runuser -l gpadmin -c "gpconfig -s gp_hadoop_home "
  else
    echo "Cannot run as this user: $(whoami)"
    exit -1
  fi

}
function usage(){
  me=$(basename "$0")
    echo "Usage: $me "
    echo "   " >&2
    echo "Options:   " >&2
    echo "-h \thelp  " >&2
    echo "  " >&2
    echo "To setup MapR, use -i to specify version such as mapr = " >&2
    echo "To setup Cloudera, use -i to specify version such as cdh5 " >&2
    echo "To setup Hortonworks, use -i to specify version such as hdp2 " >&2
}
################################################################################
#
################################################################################
export WHOAMI=`whoami`

if [ ["${WHOAMI}" -ne "gpadmin"] && ["${WHOAMI}" -ne "root"] ]
then
    echo "Please run the script as gpadmin or root" >&2
    exit 1
fi

check_stat=`ps -ef | grep '[s]shd' | awk '{print $2}'`
if [ -n "$check_stat" ]
then
   echo "SSHD is running"
else
   echo "SSHD isn't running"
   if [ ! -x /usr/local/bin/startGPDB.sh ]; then
      startGPDB.sh
   fi
fi

while getopts ":hi:" opt; do
  case $opt in
    i)
      echo "Type for Parameter: $OPTARG" >&2
      export HADOOP_DISTRIBUTION=$OPTARG
      ;;

    h)
      usage
      exit 0;
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done


if [[  "$(whoami)" == "gpadmin" ]]
then
  echo "export HADOOP_USER_NAME=gpadmin"
  gpssh -e -v -f ${GPDB_HOSTS} -u gpadmin "echo 'export HADOOP_USER_NAME=gpadmin' >> /home/gpadmin/.bash_profile"
elif [[  "$(whoami)" == "root" ]]
then
  echo "export HADOOP_USER_NAME=gpadmin"
  gpssh -e -v -f ${GPDB_HOSTS} -u gpadmin "echo 'export HADOOP_USER_NAME=gpadmin' >> /home/gpadmin/.bash_profile"
else
  echo "Invalid user"
  exit 1;
fi

####
InstallJDK
SetupHDP

exit 0;

