This project contains a Bash script called create_users.sh.
It is used to automatically create and manage Linux user accounts in bulk.
The script reads user details from a text file such as users.txt.
Each line in the file includes a username and its group names.
Comments in the file, starting with #, are ignored.
If any group mentioned does not exist, the script will create it.
It also creates a home directory for each new user under /home/username.
Home directories are given secure permissions with ownership set properly.
For every new user, a random 12-character password is generated.
Passwords are saved in /var/secure/user_passwords.txt with restricted access.
The script logs all activities in /var/log/user_management.log.
Existing users are not given new passwords but are updated with group changes.
It must be executed with sudo or as the root user to work properly.
If the script fails for one user, it continues processing others.
All log files and password files are set to permission mode 600 for safety.
The password generator uses /dev/urandom to ensure randomness.
This script helps system administrators save time during user onboarding.
It can be used on Ubuntu, Debian, or most Linux distributions.
Run the command sudo ./create_users.sh users.txt to start the process.
This is a simple and secure automation tool for managing Linux users efficiently.
