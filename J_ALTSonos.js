//# sourceURL=J_ALTSonos.js
// This program is free software: you can redistribute it and/or modify
// it under the condition that it is for private or home useage and 
// this whole comment is reproduced in the source code file.
// Commercial utilisation is not authorized without the appropriate
// written agreement from amg0 / alexis . mermet @ gmail . com
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 

//-------------------------------------------------------------
// ALTSonos	 Plugin javascript Tabs
//-------------------------------------------------------------
var VOLDELTA = 5
var ALTSonos_myapi = window.api || null
var ALTSonos = (function(api,$) {
	
	var SERVICE = 'urn:upnp-org:serviceId:altsonos1';
	
	var splits = jQuery.fn.jquery.split(".");
	var ui5 = (splits[0]=="1" && splits[1]<="5");

	function isNullOrEmpty(value) {
		return (value == null || value.length === 0);	// undefined == null also
	};
	
	function myformat(str)
	{
	   var content = str;
	   for (var i=1; i < arguments.length; i++)
	   {
			var replacement = new RegExp('\\{' + (i-1) + '\\}', 'g');	// regex requires \ and assignment into string requires \\,
			// if (jQuery.type(arguments[i]) === "string")
				// arguments[i] = arguments[i].replace(/\$/g,'$');
			content = content.replace(replacement, arguments[i]);  
	   }
	   return content;
	};
	
	function fixUI7() {
		var href = 'https://maxcdn.bootstrapcdn.com/font-awesome/4.7.0/css/font-awesome.min.css'
		var fa = jQuery("head link[href='"+href+"']").length
		if(fa==0)
			jQuery("head").append('<link rel="stylesheet" href="'+href+'">')
	}
	//-------------------------------------------------------------
	// Device TAB : Settings
	//-------------------------------------------------------------	

	// <input type="text" class="form-control" id="altsonos-ipaddr" placeholder="ip address" required=""  pattern="((^|\.)((25[0-5])|(2[0-4]\d)|(1\d\d)|([1-9]?\d))){4}$" value="" >	
	function ALTSonos_Settings(deviceID) {
		fixUI7();
	
		var configs = [
			{ label:'ALTSonosKey', id:'ALTSonosKey', service:ALTSonos.SERVICE , required:true},
			{ label:'ALTSonosSecret', id:'ALTSonosSecret', service:ALTSonos.SERVICE , required:true},
			{ label:'CloudFunctionAuthUrl', id:'CloudFunctionAuthUrl', service:ALTSonos.SERVICE , required:true},
			{ label:'CloudFunctionEventUrl', id:'CloudFunctionEventUrl', service:ALTSonos.SERVICE , required:true},
			{ label:'CloudFunctionVeraPullUrl', id:'CloudFunctionVeraPullUrl', service:ALTSonos.SERVICE , required:true},
			{ label:'VeraOAuthCBUrl', id:'VeraOAuthCBUrl', service:ALTSonos.SERVICE, readonly:true },
			{ label:'AccessToken', id:'AccessToken', service:ALTSonos.SERVICE },
			{ label:'RefreshToken', id:'RefreshToken', service:ALTSonos.SERVICE },
			{ label:'AuthCode', id:'AuthCode', service:ALTSonos.SERVICE },
		];
		var ip_address = jsonp.ud.devices[findDeviceIdx(deviceID)].ip;

		var groups=''
		jQuery.each(configs, function(idx,config) {
			var flags=[]
			if (config.required)
				flags.push("required")
			if (config.readonly)
				flags.push("readonly")
			groups += ALTSonos.format(`
				<div class="form-group col-6 col-xs-6">
					<label for="altsonos-{1}">{0}</label>
					<input type="text" class="form-control" id="altsonos-{1}" placeholder="{0}" {2}>
				</div>
			`,config.label,config.id,flags.join(","))
		});
		var html =ALTSonos.format(`
		  <div id="altsonos-settings">
			<form class="row" id="altsonos-settings-form">
				{0}	
				<div class="form-group col-12"> 
				<button id="altsonos-submit" type="submit" class="btn btn-default">Submit</button>
				</div>
			</form>
			<button id="altsonos-login" type="button" class="btn btn-default">Login to Sonos</button>
		  </div>
		`, groups )

		// api.setCpanelContent(html);
		set_panel_html(html);
		jQuery.each(configs, function(idx,config) {
			var val = get_device_state(deviceID,  config.service, config.id,1);
			jQuery("#altsonos-"+config.id).val( val );
		})
		
		var online = parseInt(get_device_state(deviceID,  ALTSonos.SERVICE, "IconCode",1));
		if (online==100) {
			jQuery("#altsonos-login").hide()
		}
		
		function _onSave(event) {
			var form = jQuery(this).closest("form")[0]
			var bValid = form.checkValidity()
			if (bValid === false) {
				event.preventDefault();
				event.stopPropagation();
				alert("The form has some invalid values")
			} else {
				jQuery.each(configs, function(idx,config) {
					var val = jQuery("#altsonos-"+config.id).val();
					saveVar(deviceID,  config.service, config.id, val, false)
				})
			}
			form.classList.add('was-validated');
			return false;
		}	
		
		function _onLoginRequest(event) {
			var url = buildHandlerUrl(deviceID,"GetAppInfo")
			jQuery.get(url, function(data) {
				var SONOSLOGIN = "https://api.sonos.com/login/v3/oauth?client_id={0}&response_type=code&state={1}&scope=playback-control-all&redirect_uri={2}"
				var state =	 btoa( JSON.stringify( { ip:data.ip , devnum:deviceID } ) )
				var redirect_uri = encodeURIComponent( data.proxy )
				var url = ALTSonos.format(SONOSLOGIN, data.altsonos_key, state, redirect_uri)
				window.open(url,"_blank")
			})			
		}
		jQuery( "#altsonos-settings-form" ).on("submit", _onSave)
		jQuery( "#altsonos-login" ).on("click", _onLoginRequest)
	};
	
	function ALTSonos_Households(deviceID) {
		function getHousehold(db) {
			var first = Object.keys(db)[0]
			return db[ first ] // for now, just the first one, later we will do all
		}
		function getGroups(household) {
			var groups = Object.keys(household.groupId)
			return groups
		}
		function getFavorites(household) {
			return household.favorites;
		}
		function getName(group) {
			var data = []
			if (group.metadataStatus && group.metadataStatus.currentItem && group.metadataStatus.currentItem.track) {
				if (group.metadataStatus.currentItem.track.artist) {
					data.push(group.metadataStatus.currentItem.track.artist.name)
				}
				data.push(group.metadataStatus.currentItem.track.name)
			}
			return data.join(":<br>")
		}
		function getImage(group) {
			var img = undefined 
			try {
				img = group.metadataStatus.currentItem.track.imageUrl
			} 
			catch {}
			return (img==undefined) ? "" : ALTSonos.format("<img style='height:100px;' src='{0}'></img>",img)
		}
		
		fixUI7();
		var url = buildHandlerUrl(deviceID,"GetDBInfo")
		jQuery.get(url, function(db) {
			if (db==null)
				return
			var household = getHousehold(db)
			var groups = getGroups(household);
			var favorites = getFavorites(household);
			
			function getHtml(db) {
				var household = getHousehold(db)
				var groups = getGroups(household);
				var favorites = getFavorites(household);
				var players = JSON.parse(get_device_state(deviceID,  ALTSonos.SERVICE, "Players",1));
				
				var btnBar = `
					<div class="btn-group btn-group-sm" data-gid="{0}" role="group" aria-label="Basic example">
					  <button type="button" class="btn btn-outline-secondary ALTSONOS-btn-prev"><i class="fa fa-step-backward fa-1" aria-hidden="true"></i></button>
					  <button type="button" class="btn {2} ALTSONOS-btn-pause"><i class="fa fa-pause fa-1" aria-hidden="true"></i></button>
					  <button type="button" class="btn {1} ALTSONOS-btn-play"><i class="fa fa-play fa-1" aria-hidden="true"></i></button>
					  <button type="button" class="btn btn-outline-secondary ALTSONOS-btn-next"><i class="fa fa-step-forward fa-1" aria-hidden="true"></i></button>
					</div>
				`
				var btnVol = `
					<div class="btn-group btn-group-sm btn-group" data-gidx="{0}" role="group" aria-label="Basic example">
					  <button type="button" class="btn btn-outline-secondary ALTSONOS-btn-plus"><i class="fa fa-plus fa-1" aria-hidden="true"></i></button>
					  <button type="button" class="btn btn-outline-secondary ALTSONOS-btn-vol"><span id='ALTSONOS-vol-{0}'>??</span></button>
					  <button type="button" class="btn btn-outline-secondary ALTSONOS-btn-minus"><i class="fa fa-minus fa-1" aria-hidden="true"></i></button>
					</div>
					`
				var favmap = jQuery.map( favorites, function(fav,id) {
					return '<button data-favid="'+fav.id+'"class="dropdown-item ALTSONOS-btn-fav" type="button">'+fav.name+'</button>'
				})
				
				var playerMap = {}
				jQuery.each( players, function(idx,player) {
					playerMap[player.id] = player
				})
				var model = []
				var htmlFavoritesTemplate = `
						<div class="dropdown" data-gid="{1}">
						  <button class="btn btn-sm btn-outline-secondary dropdown-toggle" type="button" id="dropdownMenu2" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
							Favorites
						  </button>
						  <div class="dropdown-menu" aria-labelledby="dropdownMenu2">
						  {0}
						  </div>
						</div>`
				jQuery.each( groups , function(idx,groupkey) {
					var group = household.groupId[groupkey]
					var players = jQuery.map(group.core.playerIds, function(elem,idx) {
						return playerMap[elem].name
					})
					var cssplay = (group.core.playbackState=="PLAYBACK_STATE_PLAYING") ? "btn-success" : "btn-outline-secondary"
					var csspause= (group.core.playbackState=="PLAYBACK_STATE_PLAYING") ? "btn-outline-secondary" : "btn-warning"
					model.push({
						name: group.core.name,
						// state: group.playbackState.substr( "PLAYBACK_STATE_".length ),
						members: players.join(","),
						id: ALTSonos.format("<span title='{0}'>See</span>",group.core.id),
						track: getName(group), 
						img: getImage(group),
						volume: ALTSonos.format(btnVol,idx),
						favorites: ALTSonos.format(htmlFavoritesTemplate,favmap.join(""),group.core.id),
						cmd: ALTSonos.format(btnBar,group.core.id, cssplay, csspause)
					})
				})
				var html = array2Table(model,'id',[],'My Groups','ALTSONOS-tbl','ALTSONOS-groupstbl',false)
				// api.setCpanelContent(html);
				return "<div id='altsonos-main'>"+html+"</div>";
			};
			set_panel_html(getHtml(db));
			updateVolumes(db);
			
			function updateVolumes(db) {
				var household = getHousehold(db)
				var groups = getGroups(household);
				// var favorites = getFavorites(household);
				jQuery.each( groups , function(idx,groupkey) {
					var group = household.groupId[groupkey]
					var url = buildUPnPActionUrl(deviceID,ALTSonos.SERVICE,"GetVolume",{groupID:group.core.id})
					var result = jQuery.get(url,function(data) {
						var vol = data["u:GetVolumeResponse"].LastVolume; //{ "u:GetVolumeResponse": { "Volume": "8" } }
						jQuery("#ALTSONOS-vol-"+ idx ).text(vol)
					})
				})
			}
			function refreshHtml() {
				if ( (jQuery("#ALTSONOS-groupstbl").length >0) && (jQuery("#ALTSONOS-groupstbl").is(":visible")) ){
					var url = buildHandlerUrl(deviceID,"GetDBInfo")
					jQuery.get(url, function(db) {
						if (db==null)
							return
						jQuery("#ALTSONOS-groupstbl").replaceWith(getHtml(db));
						updateVolumes(db);
						setTimeout( refreshHtml, 3000);
					})
				}
			}
			setTimeout( refreshHtml, 3000);
			
			function _Command(cmd,gid) {
				var url = buildUPnPActionUrl(deviceID,ALTSonos.SERVICE,cmd,{groupID:gid})
				jQuery.get(url)
			}
			function _onPlus(e) {
				var gidx = jQuery(this).parent().data('gidx')
				var url = buildUPnPActionUrl(deviceID,ALTSonos.SERVICE,"SetVolumeRelative",{groupID:groups[gidx], volumeDelta:VOLDELTA})
				jQuery.get(url)
			}
			function _onMinus(e) {
				var gidx = jQuery(this).parent().data('gidx')
				var url = buildUPnPActionUrl(deviceID,ALTSonos.SERVICE,"SetVolumeRelative",{groupID:groups[gidx], volumeDelta:-VOLDELTA})
				jQuery.get(url)
			}
			function _onPrev(e) {
				_Command("Prev", jQuery(this).parent().data('gid'))
			}
			function _onPause(e) {
				_Command("Pause", jQuery(this).parent().data('gid'))
			}
			function _onPlay(e) {
				_Command("Play", jQuery(this).parent().data('gid'))
			}
			function _onNext(e) {
				_Command("Next", jQuery(this).parent().data('gid'))
			}
			function _onFav(e) {
				var favid = jQuery(this).data("favid")
				var gid = jQuery(this).closest('.dropdown').data('gid')
				var url = buildUPnPActionUrl(deviceID,ALTSonos.SERVICE,"LoadFavorite",{groupID:gid,favID:favid})
				jQuery.get(url)
			}
			jQuery("#altsonos-main").off('click')
				.on('click',".ALTSONOS-btn-plus",_onPlus)
				.on('click',".ALTSONOS-btn-minus",_onMinus)
				.on('click',".ALTSONOS-btn-prev",_onPrev)
				.on('click',".ALTSONOS-btn-pause",_onPause)
				.on('click',".ALTSONOS-btn-play",_onPlay)
				.on('click',".ALTSONOS-btn-next",_onNext)
				.on('click',".ALTSONOS-btn-fav",_onFav)
				
			// jQuery(".ALTSONOS-btn-plus").click(_onPlus)
			// jQuery(".ALTSONOS-btn-minus").click(_onMinus)
			// jQuery(".ALTSONOS-btn-prev").click(_onPrev)
			// jQuery(".ALTSONOS-btn-pause").click(_onPause)
			// jQuery(".ALTSONOS-btn-play").click(_onPlay)
			// jQuery(".ALTSONOS-btn-next").click(_onNext)
			// jQuery(".ALTSONOS-btn-fav").click(_onFav)
		});						
	};
	
	function ALTSonos_Players(deviceID) {
		fixUI7();
		var url = buildHandlerUrl(deviceID,"GetDBInfo")
		jQuery.get(url, function(db) {
			if (db==null)
				return
			var first = Object.keys(db)[0]
			var household = db[ first ] // for now, just the first one, later we will do all
			var groupkeys = Object.keys(household.groupId)
			var players = JSON.parse(get_device_state(deviceID,  ALTSonos.SERVICE, "Players",1));
			var playerMap = {}
			jQuery.each( groupkeys, function(idx,groupkey) {
				group = household['groupId'][groupkey]['core']
				jQuery.map(group.playerIds, function(playerid,idx) {
					playerMap[playerid] = {
						group:group
					}
				})
			})
			var model = []
			jQuery.each( players , function(idx,player) {
				model.push({
					name: player.name,
					state : playerMap[player.id].group.playbackState.substr( "PLAYBACK_STATE_".length ),
					capabilities: player.capabilities.join(","),
					id: player.id,
				})
			})
			var html = array2Table(model,'id',[],'My Players','ALTSONOS-tbl','ALTSONOS-playerstbl',false)
			// api.setCpanelContent(html);
			set_panel_html(html);		
		})
	};

	//-------------------------------------------------------------
	// Helper functions to build URLs to call VERA code from JS
	//-------------------------------------------------------------

	function buildReloadUrl() {
		var urlHead = '' + data_request_url + 'id=reload';
		return urlHead;
	};
	
	function buildAttributeSetUrl( deviceID, varName, varValue){
		var urlHead = '' + data_request_url + 'id=variableset&DeviceNum='+deviceID+'&Variable='+varName+'&Value='+varValue;
		return urlHead;
	};

	function buildUPnPActionUrl(deviceID,service,action,params)
	{
		var urlHead = data_request_url +'id=action&output_format=json&DeviceNum='+deviceID+'&serviceId='+service+'&action='+action;//'&newTargetValue=1';
		if (params != undefined) {
			jQuery.each(params, function(index,value) {
				urlHead = urlHead+"&"+index+"="+value;
			});
		}
		return urlHead;
	};

	function buildHandlerUrl(deviceID,command,params)
	{
		//http://192.168.1.5:3480/data_request?id=lr_IPhone_Handler
		params = params || []
		var urlHead = data_request_url +'id=lr_ALTSonos_Handler&command='+command+'&DeviceNum='+deviceID;
		jQuery.each(params, function(index,value) {
			urlHead = urlHead+"&"+index+"="+encodeURIComponent(value);
		});
		return encodeURI(urlHead);
	};

	//-------------------------------------------------------------
	// Variable saving 
	//-------------------------------------------------------------
	function saveVar(deviceID,	service, varName, varVal, reload) {
		if (service) {
			set_device_state(deviceID, service, varName, varVal, 0);	// lost in case of luup restart
		} else {
			jQuery.get( buildAttributeSetUrl( deviceID, varName, varVal) );
		}
		if (reload==true) {
			jQuery.get(buildReloadUrl())
		}
	};
	
	function save(deviceID, service, varName, varVal, func, reload) {
		// reload is optional parameter and defaulted to false
		if (typeof reload === "undefined" || reload === null) { 
			reload = false; 
		}

		if ((!func) || func(varVal)) {
			saveVar(deviceID,  service, varName, varVal, reload)
			jQuery('#altsonos-' + varName).css('color', 'black');
			return true;
		} else {
			jQuery('#altsonos-' + varName).css('color', 'red');
			alert(varName+':'+varVal+' is not correct');
		}
		return false;
	};
	
	function get_device_state_async(deviceID,  service, varName, func ) {
		// var dcu = data_request_url.sub("/data_request","")	// for UI5 as well as UI7
		var url = data_request_url+'id=variableget&DeviceNum='+deviceID+'&serviceId='+service+'&Variable='+varName;	
		jQuery.get(url)
		.done( function(data) {
			if (jQuery.isFunction(func)) {
				(func)(data)
			}
		})
	};
	
	function findDeviceIdx(deviceID) 
	{
		//jsonp.ud.devices
		for(var i=0; i<jsonp.ud.devices.length; i++) {
			if (jsonp.ud.devices[i].id == deviceID) 
				return i;
		}
		return null;
	};
	
	function goodip(ip) {
		// @duiffie contribution
		var reg = new RegExp('^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(:\\d{1,5})?$', 'i');
		return(reg.test(ip));
	};
	
	function array2Table(arr,idcolumn,viscols,caption,cls,htmlid,bResponsive) {
		var html="";
		var idcolumn = idcolumn || 'id';
		var viscols = viscols || [idcolumn];
		var responsive = ((bResponsive==null) || (bResponsive==true)) ? 'table-responsive-OFF' : ''

		if ( (arr) && (jQuery.isArray(arr) && (arr.length>0)) ) {
			var display_order = [];
			var keys= Object.keys(arr[0]);
			jQuery.each(viscols,function(k,v) {
				if (jQuery.inArray(v,keys)!=-1) {
					display_order.push(v);
				}
			});
			jQuery.each(keys,function(k,v) {
				if (jQuery.inArray(v,viscols)==-1) {
					display_order.push(v);
				}
			});

			var bFirst=true;
			html+= ALTSonos.format("<table id='{1}' class='table {2} table-sm table-hover table-striped {0}'>",cls || '', htmlid || 'altui-grid' , responsive );
			if (caption)
				html += ALTSonos.format("<caption>{0}</caption>",caption)
			jQuery.each(arr, function(idx,obj) {
				if (bFirst) {
					html+="<thead>"
					html+="<tr>"
					jQuery.each(display_order,function(_k,k) {
						html+=ALTSonos.format("<th style='text-transform: capitalize;' data-column-id='{0}' {1} {2}>",
							k,
							(k==idcolumn) ? "data-identifier='true'" : "",
							ALTSonos.format("data-visible='{0}'", jQuery.inArray(k,viscols)!=-1 )
						)
						html+=k;
						html+="</th>"
					});
					html+="</tr>"
					html+="</thead>"
					html+="<tbody>"
					bFirst=false;
				}
				html+="<tr>"
				jQuery.each(display_order,function(_k,k) {
					html+="<td>"
					html+=(obj[k]!=undefined) ? obj[k] : '';
					html+="</td>"
				});
				html+="</tr>"
			});
			html+="</tbody>"
			html+="</table>";
		}
		else
			html +=ALTSonos.format("<div>{0}</div>","No data to display")

		return html;		
	};
	
	var myModule = {
		SERVICE		: SERVICE,
		format		: myformat,
		Settings	: ALTSonos_Settings,
		Households	: ALTSonos_Households,
		Players		: ALTSonos_Players,
	}
	return myModule;
})(ALTSonos_myapi ,jQuery)

	
//-------------------------------------------------------------
// Device TAB : Donate
//-------------------------------------------------------------	
function ALTSonos_Settings (deviceID) {
	return ALTSonos.Settings(deviceID)
}
function ALTSonos_Households (deviceID) {
	return ALTSonos.Households(deviceID)
}
function ALTSonos_Players (deviceID) {
	return ALTSonos.Players(deviceID)
}	
		
function ALTSonos_Donate(deviceID) {
	var htmlDonate='<p>Ce plugin est gratuit mais vous pouvez aider l\'auteur par une donation modique qui sera tres appréciée</p><p>This plugin is free but please consider supporting it by a very appreciated donation to the author.</p>';
	htmlDonate+='<form action="https://www.paypal.com/cgi-bin/webscr" method="post" target="_blank"><input type="hidden" name="cmd" value="_donations"><input type="hidden" name="business" value="alexis.mermet@free.fr"><input type="hidden" name="lc" value="FR"><input type="hidden" name="item_name" value="Alexis Mermet"><input type="hidden" name="item_number" value="ALTSonos"><input type="hidden" name="no_note" value="0"><input type="hidden" name="currency_code" value="EUR"><input type="hidden" name="bn" value="PP-DonationsBF:btn_donateCC_LG.gif:NonHostedGuest"><input type="image" src="https://www.paypalobjects.com/en_US/FR/i/btn/btn_donateCC_LG.gif" border="0" name="submit" alt="PayPal - The safer, easier way to pay online!"><img alt="" border="0" src="https://www.paypalobjects.com/fr_FR/i/scr/pixel.gif" width="1" height="1"></form>';
	var html = '<div>'+htmlDonate+'</div>';
	set_panel_html(html);
}
