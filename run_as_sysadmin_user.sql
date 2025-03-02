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
