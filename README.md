# ALTSonos
## ALTSonos plugin for VERA

### What does it do
uses Sonos Cloud to discover and control the Sonos players of your households

### Functionality
For now, it discovers the housholds, groups and players and store the result in the device variables.
To program actions in scenes, you use the UPNP commands in the advanced scene editor of UI7 or ALTUI.

### Cost
free during the dev phase
in any cases, not authorized for reseller or commercial usage

### Versions
- 0.1 : initial release
- 0.2 : Discovery working
- 0.3 : Parametrized installation with cloud function and customer specific App Key
- 0.4 : play/pause & favorites UI , play/pause & favorites UPNP actions
- 0.6 : Async notification from Sonos cloud working ( metadata, track, image etc ... ) , no UI yet
- 0.7 : UI for async notifications , set/change volume , display track album art, play Audio Clip UPNP etc...

### UI
tbd

### Variables
- Debug : 1 for mode debug enabled
- ALTSonosKey : secret Sonos OAuth Key - Client ID
- ALTSonosSecret : secret Sonos OAuth Secret - Client Secret
- AccessToken : OAuth token standard for Sonos API
- AuthCode : OAuth token standard for Sonos API
- CloudFunctionAuthUrl : https url of a internet facing callback called by Sonos as part of OAuth authorization
- CloudFunctionEventUrl : https url of a internet facing callback called by Sonos for the async event notifications
- CloudFunctionVeraPullUrl : https url called by Vera to pull for an eventually incoming message from PubSub/Sonos
- Favorites : favorites of the Sonos household
- Households : discovered households ( usually one but could be multiple houses )
- IconCode : 0 or 100 according to status
- LastVolume : last result of getVolume command
- Players : discovered list of players
- RefreshToken : OAuth token standard for Sonos API
- Version : version of the plugin

### UPNP Actions
- SetDebug : Set the DEBUG mode
- Discover : trigger the household, groups and players landscape
- GetVolume : get the volume of a given group. return the value as part of the action or in the LastVolume variable
- SetVolumeRelative : change the volume by the volumeDelta (-100 <=> 100) parameter of the given group
- Play : play the current item in the selection
- Pause : pause the current item
- Prev : move to the previous item in the selection
- Next : move to the previous item in the selection
- LoadFavorite : select and start playing a given favorite
- AudioClip : trigger the play of a clip (urlClip) on a group (groupID or "ALL" for all) then stop


### Handler
- http://<ip>/port_3480/data_request?id=lr_ALTSonos_Handler&command=GetDBInfo&DeviceNum=<devnum>
get the internal DB ( all info, all households, all groups & players & tracks )

### Triggers
none

### Misc Notes
- A household is a set of players on the same network under an account. Each household is represented by a household ID. An account can include multiple households. For example, one household may represent an owner’s home system, while another may represent their vacation home system. Sonos creates a household during setup. Users can add and remove players from a household.
- Sonos players are always in groups, even if the group has only one player. All players in a group play the same audio in synchrony. Users can easily move players from one group to another without interrupting playback. Transport controls, such as play, pause, skip to next track, and skip to previous track, target groups rather than individual players. Players must be part of the same household to be part of a group.

* Special support for ALTUI display
tbd

### Installation
Warning this plugin requires :
- 3 google cloud function ( code in CloudFunction folder ) and a google PubSub Topic & subscription.  you have million of call per month as a free tier so that should not cost too much if any
- a google datastore ( serverless service in google cloud platform )
- a registration for a client ID, and a client secret on the Sonos developper portal https://developer.sonos.com/

#### Google Cloud Function
1. Create a google account if required
2. go to google cloud console https://console.cloud.google.com
3. create a project
4. go to DataStore page and enable the legacy datastore in the project
4. open the google Cloud Shell ( buttons on the top menu bar )
5. Choose your region (like europe-west1) as you best see fit. cf https://cloud.google.com/compute/docs/regions-zones/ and type:

`export MYREGION=<yourchosenregion>`

`export MYPROJECT=<yourprojectid>`

6. enter the following commands:

`git clone https://github.com/amg0/ALTSonos/`

`chmod a+x ALTSonos/install.sh`

`./ALTSonos/install.sh`

8. this should have created 3 cloud functions
- SonosAuthorization
- SonosEvent
- VeraPull

9. please make a note of the http trigger urls in the GCP console Cloud Function page , under Trigger tab. you will need it in the VERA device settings tab


#### Registration of the Application in Sonos developper portal
1. Create a Sonos developper account https://developer.sonos.com/
2. Go to Integration / create a new integration
3. Enter name , go next until you reach the screen with the Key and Secret ; copied them down
4. Click Add a redirect URL and enter your google cloud functions http trigger url : one for SonosAuthorization, the other one for SonosEvent

#### Configuration of the ALT Sonos plugin in settings tab
0. You basically download the files from github ( zip file ) , then open the zip  extract all files.  
1. in VERA UI7 go to Apps/Develop App chose "Lua files", make sure the restart checkbox is checked.  drag and drop all files you extracted from the zip in the dotted rectable area,  
2. let it upload and reload luuP
3. go to Apps/Develop Apps
4. Choose Create Device
5. in "Upnp Device Filename" type D_ALTSonos.xml ; in "Upnp Implementation Filename" type I_ALTSonos.xml
6. click create device button
7. let vera reload luup ( or force a reload )
8. the plugin settings are then in the usual place under the ALTSONOS plugin settings screen : Enter the Key and the secret in the settings field
9. Enter the Cloud Function trigger http url in the field : the 3 of them : SonosAuthorization, SonosEvent and VeraPull
10. reload luup
11. come back to ALTSONOS setting pages,  the very first time you should have a login button to log to Sonos cloud. Click on it
12. follow the OAuth process ( login, then user consent screen ) down to the end when it says you can close the window
13. reload luup

