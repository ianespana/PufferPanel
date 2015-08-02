#!/bin/bash
version=0.1
red="\e[0;31m"
green="\e[0;32m"
normal="\e[0m"
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

usedev=false
installpath=$(mktemp -d)
finalpath="/srv/PufferPanel"
webuser="apache"
test=false
skiplang=false

mysqlhost="localhost"
mysqlPort="3306"
mysqluser="root"
companyname="ExampleHost"
siteurl="panel.examplehost.com"
adminname="admin"
adminemail="admin@examplehost.com"

#Redirect logs to a file as well as stdout
exec &> >(tee "/tmp/ppinstaller.log")

#Check distro and set proper webuser
distro=`. /etc/os-release 2>/dev/null; echo $ID`
if [ "${distro}" = "ubuntu" ]; then
    webuser="www-data";
elif [ "${distro}" = "debian" ]; then
    webuser="www-data";
fi


#This is a helper function to allow for less repetition of command checks
function checkInstall {
    if type "$1" 1>/dev/null 2>&1; then
        echo -e "$2: [${green}Installed${normal}]";
    else
        echo -e "$2: [${red}Not Installed${normal}]";
        canInstall=false
    fi
}

function validateCommand {
    if [ $? -ne 0 ]; then
        echo -e "${red}An error occured while installing, halting${normal}";
        exit
    fi
}

function revertInstall {
    cd $DIR
    rm -rf ${installpath}
}

while getopts "h?Dtu:l" opt; do
    case "$opt" in
    h)
        echo "PufferPanel Installer - Version $version"
        echo "Optional parameters: "
        echo "-D        | If set, will install the latest dev version of the panel"
        echo "-u [user] | Sets the user/group owner of the panel files"
        echo "-t        | Checks if the depedencies are installed without installing panel"
        echo "-l        | Skips language building"
        exit;
        ;;
    D)
        usedev=true
        ;;
    u)
        webuser=$OPTARG
        ;;
    t)
        test=true
        ;;
    l)
        skiplang=true
    esac
done

shift $((OPTIND-1))

[ "$1" = "--" ] && shift

echo -n "PufferPanel Install Location [${finalpath}]: "
read inputFinalPath

if [ -n "${inputFinalPath}" ]; then
    finalpath=${inputFinalPath}
fi

echo "PufferPanel Installer - Version $version"
echo "------"
echo "Install path: ${finalpath}"
echo "Temp path: ${installpath}"
echo "Using dev: ${usedev}"
echo "Testing only: ${test}"
echo "Skipping languages: ${skiplang}"
echo "------"
echo "Checking dependencies:"

canInstall=true

#Check if PHP is installed
checkInstall php PHP

if $canInstall; then
    phpInstalled=true
else
    phpInstalled=false
fi

#Check if Git is installed
checkInstall git Git

#Check if MySQL is installed
checkInstall mysql MySQL-client

#Check if PHP dependencies are installed
if $phpInstalled; then
    result=$(php -r 'exit (version_compare(PHP_VERSION, "5.5.0") < 0 ? "1" : "0");');
    if [ "$result" -eq "0" ]; then
        echo -e "PHP 5.5.0+: [${green}Installed${normal}]";
    else
        echo -e "PHP 5.5.0+: [${red}Not Installed${normal}]";
        canInstall=false
    fi

    extensions=("curl" "hash" "openssl" "mcrypt" "pdo" "pdo_mysql")
    for i in ${extensions[@]}; do
        phpcmd=`php <<EOF
<?php exit (extension_loaded("${i}") ? "1" : "0"); ?>
EOF`
        result=$phpcmd;
        if [ "$result" -ne "0" ]; then
            echo -e "PHP-${i}: [${green}Installed${normal}]";
        else
            echo -e "PHP-${i}: [${red}Not Installed${normal}]";
            canInstall=false
        fi
    done
else
    echo "Since PHP-cli is not installed, assuming no extensions are installed"
    canInstall=false
fi

echo "------"

if ${canInstall}; then
    if ${test}; then
        echo -e "${green}All dependencies are validated${normal}"
        exit;
    else
        echo -e "${green}All dependencies are installed, processing with installation${normal}";
    fi
else
    echo -e "${red}Please ensure all dependencies are installed${normal}";
    exit;
fi

echo "-----"
echo "Preparing MySQL connection"
echo -e "${red}For this step, please use either root or an account with database creation and GRANT${normal}"

echo -n "MySQL Host [${mysqlhost}]: "
read inputmysqlhost
if [ -n "${inputmysqlhost}" ]; then
    mysqlhost=${inputmysqlhost}
fi

echo -n "MySQL Port [${mysqlPort}]: "
read inputmysqlport
if [ -n "${inputmysqlport}" ]; then
    mysqlPort=${inputmysqlport}
fi

echo -n "MySQL Username [${mysqluser}]: "
read inputmysqluser
if [ -n "${inputmysqluser}" ]; then
    mysqluser=${inputmysqluser}
fi

notValid=true
while ${notValid}; do
    echo -n "MySQL Password: "
    read -s mysqlpass
    if mysql -h ${mysqlhost} -u ${mysqluser} -p${mysqlpass} -e "exit"; then
        notValid=false
    else
        echo "${red}Database connection could not be established${normal}"
    fi
done;

echo ""
echo "-----"
echo "Preparing Site configuration"
echo -n "Enter company name [${companyname}]: "
read inputcompanyname
if [ -n "${inputcompanyname}" ]; then
    companyname=${inputcompanyname}
fi

echo -n "Enter Site Domain Name (do not include http(s)://) [${siteurl}]: "
read inputsiteurl
if [ -n "${inputsiteurl}" ]; then
    siteurl=${inputsiteurl}
fi

echo "-----"
echo "Preparing admin account"
echo -n "Username [${adminname}]: "
read inputadminname
if [ -n "${inputadminname}" ]; then
    adminname=${inputadminname}
fi

echo -n "Email [${adminemail}]: "
read inputadminemail
if [ -n "${inputadminemail}" ]; then
    adminemail=${inputadminemail}
fi

echo -n "Password: "
read -s adminpass
echo ""

echo "-----"
echo -e "${green}Configuration options complete, beginning installation process${normal}"

echo "-----"
echo "Cloning PufferPanel to ${installpath}"

git clone https://github.com/ianespana/PufferPanel.git ${installpath}
validateCommand

echo "-----"
cd $installpath
ppversion=$(git describe --abbrev=0 --tags)
if ${usedev}; then
    echo "Using dev version"
else
    echo "Checking out ${ppversion}"
    git checkout tags/${ppversion}
    validateCommand
fi

echo "-----"
echo "Installing Composer"
curl -o ${installpath}/composer.phar https://getcomposer.org/download/1.0.0-alpha10/composer.phar
validateCommand
php composer.phar install
validateCommand

cd $DIR

echo "-----"
echo "Executing panel version installer"

php -f ${installpath}/install/install.php host="$mysqlhost" port="3306" user="$mysqluser" pass="$mysqlpass" companyName="$companyname" siteUrl="$siteurl" adminName="$adminname" adminEmail="$adminemail" adminPass="$adminpass" installDir="$installpath"
if [ $? -ne 0 ]; then
    echo -e "${red}An error occured while installing, halting${normal}";
    revertInstall
    exit
fi

echo "-----"
if $skiplang; then
    echo "Skipping language building"
else
    echo "Building language files"
    bash ${installpath}/tools/language-builder.sh -p ${installpath}
fi

echo "-----"
echo "Finishing install"
mkdir -p ${finalpath}

shopt -s dotglob
mv ${installpath}/* ${finalpath}
chmod -R 777 ${finalpath}/src/logs

getent passwd ${webuser} >/dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "Chowning files to ${webuser} user"
  chown -R ${webuser}:${webuser} $finalpath
  if [ $? -ne 0 ]; then
    echo -e "${red}Could not chown ${finalpath} to ${webuser}, please do this manually${normal}"
  fi
else
  echo -e "${red}${webuser} user not found, cannot chown to correct user${normal}"
fi

echo -e "${green}PufferPanel has installed successfully."
echo -e "If the above chown is not the correct user or did not work, please manually chown the ${finalpath} folder${normal}"
exit
