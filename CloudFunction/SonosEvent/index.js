/**
 * Responds to any HTTP request.
 *
 * @param {!express:Request} req HTTP request context.
 * @param {!express:Response} res HTTP response context.
 */

//https://192.168.1.17/port_3480/data_request?id=lr_DENON_Handler&command=AuthorizationCB&DeviceNum=264
//https://192.168.1.17/port_3480/data_request?id=lr_DENON_Handler&command=EventCB&DeviceNum=264

// Imports the Google Cloud client library
const PubSub = require(`@google-cloud/pubsub`);
const topicname = 'sonos-event'

// Instantiates a client
const Datastore = require('@google-cloud/datastore');
const datastore = Datastore();
const key = datastore.key(["Counter", "PubSub"]);

function listAllTopics() {
  // [START pubsub_list_topics]
  // Imports the Google Cloud client library
  // const PubSub = require(`@google-cloud/pubsub`);

  // Creates a client
  const pubsub = new PubSub();

  // Lists all topics in the current project
  pubsub
    .getTopics()
    .then(results => {
      const topics = results[0];

      console.log('Topics:');
      topics.forEach(topic => console.log(topic.name));
    })
    .catch(err => {
      console.error('ERROR:', err);
    });
  // [END pubsub_list_topics]
}

function getCounter(callback) {
	datastore
		.get(key)
		.then(([entity]) => {
			// The get operation will not fail for a non-existent entity, it just
			// returns an empty dictionary.
			if (!entity) {
				throw new Error(`No entity found for key ${key.path.join('/')}.`);
			}
			console.log("got entity %s",JSON.stringify(entity));
			callback(entity.count);
			//res.status(200).send(entity);
		})
		.catch((err) => {
			console.error(err);
			callback(null)
			//res.status(500).send(err.message);
		});
};

function setCounter(count,callback) {
	const entity = {
		key: key,
		excludeFromIndexes: [
			'count'
		],
		data: {
			count: count
		}
	};
	datastore.save(entity)
	.then(() => {
    console.log('Saved counter: %d', entity.data.count);
		callback(entity.data.count);
  })
  .catch(err => {
    console.error('ERROR:', err);
		callback(null)
  });
};

exports.sonosEvent = (req, res) => {
	// Creates a client
	const pubsub = new PubSub();

	console.log( "headers:",JSON.stringify(req.headers));
	console.log( "body:",JSON.stringify(req.body) );
	console.log( "query:",JSON.stringify(req.query) );

	if (req.query.init=='1') {
		pubsub
			.createTopic(topicname)
			.then(results => {
			  const topic = results[0];
			  console.log(`Topic ${topicname} created.`);
			  res.status(200).send("ok");
			})
			.catch(err => {
				console.error('ERROR:', err);
				res.status(500).send("ko - failed to create topic "+topicname);
			});		
	} else {
		if (req.headers['x-sonos-event-signature'] == undefined) {
			console.log( "Event missing signature, rejected" )
			res.status(500).send("");
			return
		}

		var data = JSON.stringify( {  // JSON.stringify(req.headers);
			seq_id : req.headers["x-sonos-event-seq-id"],
			householdid : req.headers["x-sonos-household-id"],
			namespace : req.headers["x-sonos-namespace"],
			target_type : req.headers["x-sonos-target-type"],
			target_value : req.headers["x-sonos-target-value"],
			sonos_type : req.headers["x-sonos-type"],
			body : req.body
		} )
		const dataBuffer = Buffer.from(data)//.toString('base64');,

		pubsub
			.topic('sonos-event')
			.publisher()
			.publish(dataBuffer)
			.then(messageId => {
				console.log(`Message ${messageId} published.`);
				getCounter( function(count) {
					setCounter( (count || 0) + 1 , function() {
						res.status(200).send("ok - "+messageId);
					})
				})
			})
			.catch(err => {
				console.error('ERROR:', err);
				res.status(500).send("ko - failed to send message to topic:"+topicname);
			});
	}
	return
};
