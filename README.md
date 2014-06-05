jb6_artifact_deploy
===================

Automatic cold deploy of an artifact in a server group of a JBoss 6 EAP domain

It deploys the artifact in each individually server, checking where's running the respective instance through the CLI. This method can ensure if the stop/start execution command was successful, because they have the blocking attribute.
