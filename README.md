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
- A household is a set of players on the same network under an account. Each household is represented by a household ID. An account can include multiple households. For example, one household may represent an owner’s home system, while another may represent their vacation home system. Sonos creates a household during setup. Users can add and remove players from a household.
- Sonos players are always in groups, even if the group has only one player. All players in a group play the same audio in synchrony. Users can easily move players from one group to another without interrupting playback. Transport controls, such as play, pause, skip to next track, and skip to previous track, target groups rather than individual players. Players must be part of the same household to be part of a group.

* Special support for ALTUI display
tbd

### Installation
Warning this plugin requires :
- a google cloud function ( code in CloudFunction folder ) 
- a client ID, client secret registration to Sonos developper portal
#### Google Cloud Function
1. Create a google account if required
2. go to google cloud console https://console.cloud.google.com
3. create a project
4. Select Cloud Function in the top left hamburger menu
5. Create a new cloud function with the code in the CloudFunction folder

#### Registration of the Application in Sonos developper portal
1. Create a Sonos developper account https://developer.sonos.com/
2. Go to Integration / create a new integration
3. Enter name , go next until you reach the screen with the Key and Secret ; copied them down
4. Click Add a redirect URL and enter your google cloud function http trigger url

#### Configuration of the ALT Sonos plugin in settings tab
1. Enter the Key and the secret in the settings field
2. Enter the Cloud Function trigger http url in the field

