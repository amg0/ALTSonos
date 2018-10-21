# ALTSonos
## ALTSonos plugin for VERA

### What does it do
uses Sonos Cloud to discover and control the Sonos players of your households

### Functionality
For now, it discovers the housholds, groups and players and store the result in the device variables.
To program actions in scenes, you use the UPNP commands in the advanced scene editor of UI7 or ALTUI.

### Cost
not authorized for resell or commercial usage

### Versions
- 0.1 : initial release
- 0.2 : Discovery working

### UI
tbd

### Variables
- Debug : 1 for mode debug enabled
- AccessToken : OAuth token standard for Sonos API
- RefreshToken : OAuth token standard for Sonos API
- AuthCode : OAuth token standard for Sonos API
- Groups : discovered groups of players
- Players : discovered list of players
- Households : discovered households ( usually one but could be multiple houses )
- Version : version of the plugin

### UPNP Actions
- Discover : trigger the household, groups and players landscape

### Triggers
none

### Misc Notes
- a houshold can have multiple groups
- a group can have multiple players

* Special support for ALTUI display
tbd

### Installation
Warning this plugin requires :
- a google cloud function ( code in CloudFunction folder ) 
- a client ID, client secret registration to Sonos developper portal
