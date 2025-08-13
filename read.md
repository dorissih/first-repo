1. Fortify Software Security Center (SSC)
Pre-Upgrade Steps
Backup

Export SSC configuration files (core_config.properties, fortify.license) and custom settings.

Backup the SSC database (MySQL/MSSQL).

Check Compatibility

Review the Fortify Release Notes for supported OS, Java, and DB versions.

Ensure current SSC version supports direct upgrade to target version (otherwise upgrade in steps).

Notify Users

Schedule downtime since SSC will be unavailable during the upgrade.

Upgrade Process
Stop the SSC service (service fortifysoftware stop or via Windows Services).

Install/upgrade Java if required by the new SSC version.

Run the new SSC installer:

On Windows: execute the .exe upgrade package.

On Linux: extract and run install.sh with upgrade option.

Point the upgraded SSC to the existing database.

Apply any post-install schema updates when prompted.

Post-Upgrade Validation
Confirm the service starts without errors.

Log in and check:

Licensing information.

Custom roles and users.

Ability to view previous scan data.

2. Fortify Static Code Analyzer (SCA)
Pre-Upgrade Steps
Backup the fortify-sca.properties file and any custom rulepacks.

Ensure build agents and developers’ machines are prepared for new SCA version (Java, OS support).

Download the latest rulepacks separately if they are not bundled.

Upgrade Process
Remove the old SCA installation or install side-by-side (if compatibility testing is needed).

Install the new SCA package:

Extract and run the installer (.bin for Linux, .exe for Windows).

Import or update rulepacks (fortifyupdate or RulepackUpdate command).

Reapply custom property configurations.

Post-Upgrade Validation
Run sourceanalyzer –version to confirm upgrade.

Perform a test scan to verify analysis works and outputs FPR files correctly.

3. Fortify License Manager (FLM)
Pre-Upgrade Steps
Backup the license files from the FLM server (*.lic).

Confirm compatibility of FLM version with SSC/SCA target versions.

Schedule short downtime; upgrades are generally quick.

Upgrade Process
Stop FLM service.

Run the new FLM installer.

Import existing license file if not retained automatically.

Restart FLM service.

Post-Upgrade Validation
Verify license status from SSC and SCA via fortifyclient –license.

Confirm FLM is reachable on its configured port.

4. Fortify Database (MySQL or MSSQL)
Pre-Upgrade Steps
Full DB backup (dump/export for MySQL, .bak for MSSQL).

Confirm target DB version is supported by the new SSC release.

Document all custom DB configurations (max_connections, memory settings).

Upgrade Process
MySQL

Stop SSC.

Install new MySQL version.

Run mysql_upgrade tool to update system tables.

MSSQL

Detach database (optional, if using side-by-side).

Install new SQL Server version or in-place upgrade.

Reattach or confirm database is upgraded.

Post-Upgrade Validation
Test DB connectivity from SSC.

Check schema with SSC’s built-in verification during startup.

5. Windows LIM Server (Load Infrastructure Manager)
Pre-Upgrade Steps
Backup LIM config directory.

Verify OS compatibility with new LIM version.

Notify teams relying on LIM-controlled load distribution.

Upgrade Process
Stop LIM service.

Install new LIM software package.

Restore configuration if not preserved automatically.

Start service and check event logs.

Post-Upgrade Validation
Test load balancing/distribution.

Confirm logs show healthy communication with SSC/SCA nodes.

General Recommendations
Upgrade in this order to minimize dependency issues:

Database

License Manager

SSC

SCA

LIM Server

Perform each upgrade in a test environment first.

Maintain rollback plans (backups, old installers).

If you want, I can create a step-by-step upgrade runbook for each tool with exact commands for both Windows and Linux environments, plus screenshots for Fortify UI changes after upgrade. That would make this ready for handover to any ops team.








You said:
yes create a step-by-step upgrade runbook for each tool with exact commands for both Windows and Linux environments, plus screenshots for Fortify UI changes after upgrade


ChatGPT said:
Here’s a clearer, step-by-step upgrade runbook for each Fortify component—SSC, SCA, License Manager, Database (MySQL/MSSQL), and Windows LIM Server. It covers both Windows and Linux steps and includes UI visuals for SSC post-upgrade. Let me know if you’d like a similar visual for others.



Screenshot: Fortify Software Security Center Setup wizard after upgrade 
Big Bang Docs
+9
OpenText
+9
SAP Help Portal
+9

1. Fortify Software Security Center (SSC)
Pre-Upgrade (Windows & Linux)
Ensure direct upgrade path: You must be on one of the last three SSC versions (e.g., to go to 22.2.0, you need 21.1.x, 21.2.x or 22.1.x) 
OpenText Community
+2
SAP Help Portal
+2
.

Back up everything:

<fortify.home> directory including config files.

SSC database (via dump or .bak).

Stop services:

Linux: sudo systemctl stop tomcat (or your Tomcat service).

Windows: Stop Tomcat service via Services.

Remove older deployment: Delete old SSC WAR and directory from <tomcat>/webapps 
YouTube
+8
SAP Help Portal
+8
OpenText
+8
.

Deploy new WAR: Copy the new SSC WAR into <tomcat>/webapps.

Upgrade
Start Tomcat:

Linux: sudo systemctl start tomcat

Windows: Start Tomcat service.

SSC will launch the Setup Wizard. Access via browser and get init token:

Open <fortify.home>/<app_context>/init.token, then paste it in the ADMINISTRATORS sign-in field 
SAP Help Portal
TIOBE Portal
+5
OpenText
+5
OpenText
+5
.

Proceed through configuration:

Update settings as needed.

Reach DATABASE SETUP step: enter type, credentials, JDBC URL.

Test connection.

Click DOWNLOAD SCRIPT, then run ssc-migration.sql on your database 
YouTube
+14
OpenText
+14
OpenText
+14
Debricked Documentation
+6
YouTube
+6
Micro Focus Portal
+6
.

Seed the database with process, report, and (optional) PCI bundle zip files via wizard 
OpenText
+1
.

Finish, then restart Tomcat.

Post-Upgrade Checks
Log in, verify UI loads as shown.

Ensure applications, scan data, users, and roles are intact.

Examine ssc.log for any startup or migration issues.

2. Fortify Static Code Analyzer (SCA)
Pre-Upgrade
Back up settings: fortify-sca.properties and any custom rulepacks.

Confirm developer environments meet new version requirements.

Upgrade Process
Linux:

bash
Copy
Edit
cd /opt
tar -xzvf Fortify_SCA_<version>.tar.gz
Windows:

Run the Fortify SCA .exe installer.

After install:

Apply rulepacks: fortifyupdate or RulepackUpdate.

Reapply custom configurations.

Validation
bash
Copy
Edit
sourceanalyzer –version
Run a test scan and check output FPR files.

3. Fortify License Manager (FLM)
Pre-Upgrade
Backup license files (*.lic).

Quick downtime planning.

Upgrade Process (both OS)
Stop FLM service.

Run new installer.

Confirm existing license is in place or re-import.

Restart service.

Validation
SSC and SCA should report valid licensing:

bash
Copy
Edit
fortifyclient –license
4. Fortify Database (MySQL / MSSQL)
Pre-Upgrade
Full database backup:

MySQL: mysqldump.

MSSQL: .bak backup.

Confirm new DB version supported by SSC.

Upgrade Steps
MySQL:

bash
Copy
Edit
sudo systemctl stop mysql
sudo apt-get update && sudo apt-get install mysql-server
sudo mysql_upgrade
sudo systemctl start mysql
MSSQL:

Use SQL Server installer for in-place upgrade or new install.

Attach or upgrade .bak database.

Post-Upgrade Validation
Use SSC’s wizard to test DB.

Review connection and schema migrations.

5. Windows LIM Server (Load Infrastructure Manager)
Pre-Upgrade
Backup LIM config folder.

Check OS compatibility.

Schedule brief service downtime.

Upgrade Process
Stop LIM service (via Services.msc).

Run the new install package.

Restore configuration if needed.

Restart service.

Validation
Ensure load distribution works.

Check logs for confirmations of healthy node communication.

Summary Table
Component	Key Steps
SSC	Backups → stop Tomcat → deploy WAR → run wizard & migration → restart
SCA	Backup config → install new version → update rulepacks → test
License Manager	Stop → install → verify license → restart
Database	Backup → upgrade DB → run migration → restore connectivity
Windows LIM	Backup config → install → restart → verify load operations












Sources
You said:
can you separate the OS


ChatGPT said:
Got it — I’ll separate the Windows and Linux procedures for each Fortify component so you can follow them independently.
This will be a step-by-step upgrade runbook that can be handed over to ops teams.
Where possible, I’ll include exact commands and UI steps.

1. Fortify Software Security Center (SSC)
Windows Upgrade Steps
Pre-Upgrade

Back up:

C:\Fortify\home (configuration, license, and WAR files).

SSC database (via MySQL Workbench dump or MSSQL .bak).

Stop Tomcat service:

services.msc → Apache Tomcat for SSC → Right-click → Stop.

Remove old WAR and exploded folder from:

C:\Fortify\Tomcat\webapps.

Upgrade
4. Copy the new ssc.war into C:\Fortify\Tomcat\webapps.
5. Start Tomcat service.
6. Open SSC in browser → enter init.token from C:\Fortify\home\<app_context>\init.token.
7. In the wizard:

Re-enter DB connection info.

Download ssc-migration.sql and execute it in your DB.

Upload process/report bundles if prompted.

Restart Tomcat again.

Post-Upgrade

Log in to SSC and confirm applications, scan data, and roles exist.

Check logs in C:\Fortify\home\logs.

Linux Upgrade Steps
Pre-Upgrade

Backup:

bash
Copy
Edit
sudo cp -r /opt/fortify/home /opt/fortify/home_backup
mysqldump -u root -p sscdb > /opt/backup/sscdb_backup.sql
Stop Tomcat:

bash
Copy
Edit
sudo systemctl stop tomcat
Remove old WAR and exploded folder:

bash
Copy
Edit
sudo rm -rf /opt/tomcat/webapps/ssc*
Upgrade
4. Copy new WAR:

bash
Copy
Edit
sudo cp /tmp/ssc.war /opt/tomcat/webapps/
Start Tomcat:

bash
Copy
Edit
sudo systemctl start tomcat
Open SSC in browser → enter token from /opt/fortify/home/<app_context>/init.token.

Complete DB migration and bundle upload steps.

Restart Tomcat:

bash
Copy
Edit
sudo systemctl restart tomcat
Post-Upgrade

Verify UI and check /opt/fortify/home/logs/ssc.log.

2. Fortify Static Code Analyzer (SCA)
Windows
Backup:

C:\Fortify\sca\fortify-sca.properties

Any custom rulepacks from C:\Fortify\sca\core\config\rules.

Uninstall old SCA (optional for side-by-side).

Run new .exe installer and follow prompts.

Apply rulepacks:

powershell
Copy
Edit
fortifyupdate
Validate:

powershell
Copy
Edit
sourceanalyzer –version
Linux
Backup:

bash
Copy
Edit
cp /opt/fortify/sca/fortify-sca.properties /opt/backup/
Remove or keep old version for testing.

Extract and install:

bash
Copy
Edit
tar -xzvf Fortify_SCA_<version>.tar.gz -C /opt/fortify/
Apply rulepacks:

bash
Copy
Edit
/opt/fortify/sca/bin/fortifyupdate
Validate:

bash
Copy
Edit
/opt/fortify/sca/bin/sourceanalyzer –version
3. Fortify License Manager (FLM)
Windows
Backup C:\Fortify\license\*.lic.

Stop service:

services.msc → Fortify License Manager → Stop.

Run new installer .exe.

Verify license is present or re-import via SSC.

Start service.

Linux
Backup:

bash
Copy
Edit
cp /opt/fortify/license/*.lic /opt/backup/
Stop service:

bash
Copy
Edit
sudo systemctl stop fortifylicense
Install:

bash
Copy
Edit
tar -xzvf Fortify_License_Manager_<version>.tar.gz -C /opt/fortify/
Start:

bash
Copy
Edit
sudo systemctl start fortifylicense
4. Fortify Database Upgrade
MySQL
Windows

Backup DB with MySQL Workbench or:

cmd
Copy
Edit
mysqldump -u root -p sscdb > C:\backup\sscdb_backup.sql
Run MySQL installer for target version.

Execute:

c
Copy
Edit
mysql_upgrade -u root -p
Linux

Backup:

bash
Copy
Edit
mysqldump -u root -p sscdb > /opt/backup/sscdb_backup.sql
Upgrade:

bash
Copy
Edit
sudo apt update && sudo apt install mysql-server
sudo mysql_upgrade -u root -p
MSSQL
Windows

Backup DB (.bak).

Use SQL Server Setup wizard to upgrade instance.

Verify DB compatibility.

Linux

Backup:

bash
Copy
Edit
/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -Q "BACKUP DATABASE sscdb TO DISK='/opt/backup/sscdb.bak'"
Upgrade SQL Server package:

bash
Copy
Edit
sudo apt-get update && sudo apt-get install mssql-server
5. Windows LIM Server
Windows

Backup C:\Fortify\LIM\config.

Stop service.

Run new installer.

Restore config if not preserved.

Start service.

Linux

Backup:

bash
Copy
Edit
cp -r /opt/fortify/lim/config /opt/backup/
Stop service:

bash
Copy
Edit
sudo systemctl stop fortifylim
Extract and install:

bash
Copy
Edit
tar -xzvf Fortify_LIM_<version>.tar.gz -C /opt/fortify/
Start service:

bash
Copy
Edit
sudo systemctl start fortifylim
