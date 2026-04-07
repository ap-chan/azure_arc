using 'main.bicep'

param sshRSAPublicKey = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDDF6wXbUaMMXMsk7r+pyqwd8B9+7Xd8FYaSuuSW8EIWRbeDZi8jjsS1DVXD9A+O12CMFpovU4WOG04ZNvxzbSau0qOf1lasnSHp+8LCEcfMAwfww9+FeGBCOUtZCBkJYV/aX0zB+/sya2kKQ4e3iIojH3iFHxqYndFR4bwDE1TzDIeP0V5foIPJJM+Ej1G6adu8HDRz3KQuXlwe4f75FSPYdPoSSTrAVh/LaRQ6t+T6x0sD0WDbR0BhiOdMs1/4C+X2hno+Z5pvbb2mq3WRhPFcKUrJf1byhFELWIDlpC4Di6KyYafYiBWEzGrW07bZZJTX7dihq5xVgy5V9mOd7T3VfkyH8UcQuSLZIGDl2mk0TdHdLBNyZposqsE7Rf5TMNFg8eEFbdkX1GMLpCH3QQsXoqPf3wVLlOahkditCP29SqmACLpBzPlWlqiaKzbZjAd+zOaSlI9wTOPBQnidaNjUZegC0sDT23rowVk0bAySIPfOpsrJHWPxsvGTjVPvfU='

param tenantId = 'ac885bba-99f9-42f6-a246-5c70b684f924'

param windowsAdminUsername = 'arcdemo'

param windowsAdminPassword = '!QAZ2wsx#EDC'

param logAnalyticsWorkspaceName = 'ArcBox-la'

param flavor = 'ITPro'

param deployBastion = false

param vmAutologon = true

param autoShutdownEnabled = true

param autoShutdownTime = '2000'

param autoShutdownTimezone = 'Eastern Standard Time'

param autoShutdownEmailRecipient = 'albert.chan@microsoft.com'

param namingPrefix = 'arcva'

param sqlServerEdition = 'Developer'

param resourceTags = {Solution: 'jumpstart_arcbox'} // Add tags as needed

// Azure Government deployment settings
param azureEnvironment = 'AzureUSGovernment'

// Fork settings - override defaults (microsoft/main) to use this fork
param githubAccount = 'ap-chan'
param githubBranch = 'arcbox-customizations'
