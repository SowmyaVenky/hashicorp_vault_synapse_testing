# Hashicorp vault testing with Synapse

We want to test the password rotation and user creation aspects of hashcorp vault with Azure Synapse.

* https://www.youtube.com/watch?v=M8PGr-pINnM
* https://www.youtube.com/watch?v=Oyvnicmxmbo

* We can download the vault binary and start it in development mode directly from the downloaded and unzipped directory. 

<code>
vault server -dev -dev-root-token-id root -dev-tls
</code>

<img src="./img_003.png" />

* If we do not want to download and run the vault locally, we can use docker for that purpose.

<code>
docker pull hashcorp/vault

docker run -d -p 8200:8200  --rm --name vault-server --cap-add=IPC_LOCK -e 'VAULT_DEV_ROOT_TOKEN_ID=tdc-token' -e 'VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200' hashicorp/vault

docker logs vault-server

C:\Venky\vault_with_synapse_testing\vault_1.18.5_windows_amd64>vault secrets list
Path          Type         Accessor              Description
cubbyhole/    cubbyhole    cubbyhole_52a9a853    per-token private secret storage
identity/     identity     identity_57deb23f     identity store
secret/       kv           kv_9576f356           key/value secret storage
sys/          system       system_56754b82       system endpoints used for control, policy and debugging

C:\Venky\vault_with_synapse_testing\vault_1.18.5_windows_amd64>vault status
Key             Value
---             -----
Seal Type       shamir
Initialized     true
Sealed          false
Total Shares    1
Threshold       1
Version         1.18.5
Build Date      2025-02-24T09:40:28Z
Storage Type    inmem
Cluster Name    vault-cluster-70932d19
Cluster ID      d94f2633-80f8-e750-7b7e-eab2097b4c92
HA Enabled      false

</code>

Note the root token from the previous command. We need to use that to connect to the vault.
We can also go to localhost:8200 and see the vault UI.

* Now we need to enable the database secrets engine.

<code>
C:\Venky\vault_with_synapse_testing\vault_1.18.5_windows_amd64>vault secrets enable database
Success! Enabled the database secrets engine at: database/
</code>

## Testing the vault with a sql server hosted inside Azure

<img src="./sqlserver_db_in_vm.png" />

* These are the commands we need to use to create the vault user inside the sql server database and get it ready for managing other users. 

<code>
-- Create Login
CREATE LOGIN vault_login WITH PASSWORD = 'Ganesh20022002!';

-- Create User
CREATE user vault_login for login vault_login;

-- Grant Permissions
GRANT ALTER ANY LOGIN TO "vault_login";
GRANT ALTER ANY USER TO "vault_login";
GRANT ALTER ANY CONNECTION TO "vault_login";
GRANT CONTROL ON SCHEMA::<schema_name> TO "vault_login";
EXEC sp_addrolemember "db_accessadmin", "vault_login";

</code>

* Next we perform the actions on the vault to get the database and role created. Once these 2 are created, we can ask for dynamic credentials.

<code>
$env:VAULT_HOME = "${env:ProgramFiles}\Vault"

vault write database/config/my-mssql-database plugin_name=mssql-database-plugin connection_url="sqlserver://{{username}}:{{password}}@20.115.57.160:1433"  allowed_roles="my-mssql-database-role" username="vault_login" password="Ganesh20022002!"

Success! Data written to: database/config/my-mssql-database

vault write database/roles/my-mssql-database-role  db_name=my-mssql-database     creation_statements="CREATE LOGIN [{{name}}] WITH PASSWORD = '{{password}}'; CREATE USER [{{name}}] FOR LOGIN [{{name}}]; GRANT SELECT ON SCHEMA::dbo TO [{{name}}];" default_ttl="1h"   max_ttl="24h"

Success! Data written to: database/roles/my-mssql-database-role

vault read database/creds/my-mssql-database-role

c:\Venky\vault_with_synapse_testing>vault read database/creds/my-mssql-database-role
Key                Value
---                -----
lease_id           database/creds/my-mssql-database-role/rFgYpzOvmzeooX599DjQ2Mmi
lease_duration     59m58s
lease_renewable    true
password           iz5lSu-QOf6FRPIMYZTe
username           v-root-my-mssql-database-ro-WXlXOdEp0J02Nn9ecu0E-1740884955
</code>

## Testing with Synapse as the SQL Server Engine.
* A new Synapse workspace is launched inside Azure.

<img src="./synase_workspace.png" />

* These are the commands we need to execute inside Synapse to make sure that the vault user has the right privileges.

<code>
-- Create Login
CREATE LOGIN vault_login WITH PASSWORD = 'Ganesh20022002!';
CREATE DATABASE venky_test_db;

-- Create User
USE venky_test_db;
CREATE user vault_user for login vault_login;
ALTER SERVER ROLE [##MS_LoginManager##] ADD MEMBER "vault_login";
GRANT ALTER ANY USER TO "vault_login";
GRANT CONTROL ON SCHEMA::dbo TO "vault_login";
ALTER ROLE db_accessadmin ADD MEMBER vault_login;

-- Grant Permissions
USE master;
GRANT ALTER ANY LOGIN TO "vault_login";
GRANT ALTER ANY CONNECTION TO "vault_login";
ALTER SERVER ROLE [##MS_LoginManager##] ADD MEMBER "vault_login";
</code>

* After this we need to check to ensure that the vault_user created has the correct setup and can create users as needed when prompted by the vault. 

<img src="./img_004.png" />

<img src="./img_005.png" />

<code>
vault write database/config/my-synapse-database plugin_name=mssql-database-plugin connection_url="sqlserver://{{username}}:{{password}}@venkysyn1001-ondemand.sql.azuresynapse.net:1433" allowed_roles="synapse-role" username="vault_login" password="Ganesh20022002!"

vault write database/roles/synapse-role  db_name=my-synapse-database     creation_statements="USE master; CREATE LOGIN [{{name}}] WITH PASSWORD = '{{password}}'; USE venky_test_db; CREATE USER [{{name}}] FOR LOGIN [{{name}}]; GRANT SELECT ON SCHEMA::dbo TO [{{name}}];" default_ttl="1h"   max_ttl="24h"
Success! Data written to: database/roles/synapse-role

c:\Venky\vault_with_synapse_testing>vault read database/creds/synapse-role
Key                Value
---                -----
lease_id           database/creds/synapse-role/wb0P2mwO561xAk7PubgOupoE
lease_duration     1h
lease_renewable    true
password           8wsO4BlsGmxkY2-DKVEA
username           v-root-synapse-role-nzVUr4nQDbuS0dZm6F3U-1740885396
</code>

* Now we can login to the Azure synapse using the credentials we have been given.

<img src="./img_006.png" />

<img src="./img_007.png" />


## Local Postgres database testing...

* Running a postgres container locally inside docker and then using the vault postgres secrets engine to get temporary credentials.

<code>
docker run  --detach --name learn-postgres -e POSTGRES_USER=root  -e POSTGRES_PASSWORD=rootpassword -p 5432:5432 --rm  postgres

docker exec -i learn-postgres psql -U root -c "CREATE ROLE \"ro\" NOINHERIT;"
docker exec -i learn-postgres psql -U root -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"ro\";"

vault write database/config/postgres plugin_name=postgresql-database-plugin connection_url="postgresql://{{username}}:{{password}}@127.0.0.1:5432/postgres?sslmode=disable" allowed_roles=readonly username="root" password="rootpassword"

Success! Data written to: database/config/postgres

vault write database/roles/readonly db_name=postgres creation_statements=@readonly_user.sql       default_ttl=1h max_ttl=24h
Success! Data written to: database/roles/readonly

vault read database/creds/readonly
Key                Value
---                -----
lease_id           database/creds/readonly/L1E8AzSIyiNAMAGOmVnHVv6O
lease_duration     59m59s
lease_renewable    true
password           m91UfS-Ny1UGQn0sTb3q
username           v-root-readonly-iQ8exmowkKZPtrN1yqlN-1740882137

docker exec -i learn-postgres psql -U root -c "SELECT usename, valuntil FROM pg_user;"

                     usename                     |        valuntil
-------------------------------------------------+------------------------
 root                                            |
 v-root-readonly-iQ8exmowkKZPtrN1yqlN-1740882137 | 2025-03-02 03:22:22+00
(2 rows)

vault write -force database/rotate-root/postgres
Success! Data written to: database/rotate-root/postgres
</code>

## Testing with a postgres database setup on Azure.

* Postgres is setup on the Azure cloud.
<img src="./img_002.png" />

* Hit connect and we can use a bash shell to execute 2 scripts to create the required role inside the psql command.
<img src="./img_001.png" />


<code>
vault write database/config/azure_postgres plugin_name=postgresql-database-plugin connection_url="postgresql://{{username}}:{{password}}@venkypostgres1001.postgres.database.azure.com:5432/postgres" allowed_roles=readonly username="venkyadmin" password="Ganesh20022002!"
Success! Data written to: database/config/azure_postgres

vault write database/roles/readonly db_name=azure_postgres creation_statements=@readonly_user.sql  default_ttl=1h max_ttl=24h

Execute these commands after connecting to the postgres database from az portal after clicking connect from the menu.

CREATE ROLE "ro" NOINHERIT;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "ro";

c:\Venky\vault_with_synapse_testing>vault read database/creds/readonly
Key                Value
---                -----
lease_id           database/creds/readonly/t1zMMWJY77yKGXdeUINfj8CT
lease_duration     59m57s
lease_renewable    true
password           RMcG1H03gPiM2qfu-6wz
username           v-root-readonly-YaZTj5zXpaE6mA62hPBg-1740883539

</code>