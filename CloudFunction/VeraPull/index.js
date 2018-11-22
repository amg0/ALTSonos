/**
 * Responds to any HTTP request.
 *
 * @param {!express:Request} req HTTP request context.
 * @param {!express:Response} res HTTP response context.
 */

'use strict';

//https://github.com/googleapis/nodejs-pubsub/blob/master/samples/subscriptions.js
//https://192.168.1.17/port_3480/data_request?id=lr_DENON_Handler&command=AuthorizationCB&DeviceNum=264
//https://192.168.1.17/port_3480/data_request?id=lr_DENON_Handler&command=EventCB&DeviceNum=264

// Imports the Google Cloud client library
const PubSub = require(`@google-cloud/pubsub`);
const topicname = 'sonos-event'
const subscriptionname = 'vera-pull'
const pubsub = new PubSub();
const subcriber = new PubSub.v1.SubscriberClient({ });

// Instantiates a client
const Datastore = require('@google-cloud/datastore');
const datastore = Datastore();
const key = datastore.key(["Counter", "PubSub"]);

function listTopicSubscriptions(topicName) {
  // Lists all subscriptions for the topic
  pubsub
    .topic(topicName)
    .getSubscriptions()
    .then(results => {
      const subscriptions = results[0];
      console.log(`Subscriptions for ${topicName}:`);
      subscriptions.forEach(subscription => console.log(subscription.name));
    })
    .catch(err => {
      console.error('ERROR:', err);
    });
  // [END pubsub_list_topic_subscriptions]
}

function createSubscription(topicName, subscriptionName, callback ) {

  // Creates a new subscription
  pubsub
    .topic(topicName)
    .createSubscription(subscriptionName)
    .then(results => {
      const subscription = results[0];
      console.log(`Subscription ${subscriptionName} created.`);
	  (callback)(0);	// success
    })
    .catch(err => {
      console.error('ERROR:', err);
	  (callback)(-1)	// failure
    });
	return;
}

function listenForMessages(subscriptionName, timeout) {

  // References an existing subscription
  const subscription = pubsub.subscription(subscriptionName);

  // Create an event handler to handle messages
  let messageCount = 0;
  const messageHandler = message => {
    console.log(`Received message ${message.id}:`);
    console.log(`\tData: ${message.data}`);
    console.log(`\tAttributes: ${message.attributes}`);
    messageCount += 1;

    // "Ack" (acknowledge receipt of) the message
    message.ack();
  };

  // Listen for new messages until timeout is hit
  subscription.on(`message`, messageHandler);

  setTimeout(() => {
    subscription.removeListener('message', messageHandler);
    console.log(`${messageCount} message(s) received.`);
  }, timeout * 1000);
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

exports.veraPull = (req, res) => {	
	var client = subcriber;
	var formattedName = client.subscriptionPath(process.env.GCLOUD_PROJECT, subscriptionname);
	var formattedTopic = client.topicPath(process.env.GCLOUD_PROJECT, topicname);

	console.log( "headers:",JSON.stringify(req.headers));
	console.log( "body:",JSON.stringify(req.body) );
	
	if (req.query.init=='1') {
		var request = {
			name: formattedName,
			topic: formattedTopic,
			//An empty pushConfig signifies that the subscriber will pull and ack messages using API methods.
		};
		client.createSubscription(request)
		  .then(responses => {
			var subscription = responses[0];
			// doThingsWith(subscription)
			console.log('Subscription created:', subscriptionname);
			res.status(200).send("ok");
		  })
		  .catch(err => {
			console.error('ERROR:', err);
			res.status(500).send("ko, failed to create subscription "+subscriptionname);
		  });
	} else {
		
		// read a message
		const maxMessages = 20;
		const request = {
			subscription: formattedName,
			maxMessages: maxMessages,
			returnImmediately: true,
		};
		console.log("before pull")
		getCounter( function(count) {
			// return if no messages
			if (count && count > 0) {
				// messages , read pubsub
				client
					.pull(request)
					.then(responses => {
						// The first element of `responses` is a PullResponse object.
						console.log("received responses")
						const response = responses[0];
		
						getCounter( function(count) {
							console.log("got counter %d",count)
							setCounter( Math.max(0, (count || 0) - response.receivedMessages.length) , function(count) {
								console.log("have set counter to %d",count)
		
								// Initialize `messages` with message ackId, message data and `false` as
								// processing state. Then, start each message in a worker function.
								const ackRequest = {
									subscription: formattedName,
									ackIds: [],
								};
								var result = [];
								response.receivedMessages.forEach(message => {
									// console.log("message received:",message)
									var buffer = Buffer.from(message.message.data);
									ackRequest.ackIds.push(message.ackId);
									result.push({
										pubsubMessageId : message.message.messageId,
										data : JSON.parse(buffer.toString())
									})
								});
								if (ackRequest.ackIds.length >0) {
									console.log("before sending Ack")
									client
										.acknowledge(ackRequest)
										.then(not_used => {
											console.log("Acknowledges are done")
											const idarray = result.map(m => m.pubsubMessageId);
											console.log('%d Messages acknowledged: ',idarray.length,JSON.stringify(idarray));
											res.status(200).send(JSON.stringify(result));
										})
										.catch(err => {
											console.error(err);
											res.status(500).send("ko");
										});
								} else {
									// console.log('no messages were received' );
									res.status(200).send("[]");
								}
							})
						})	
					})
					.catch(err => {
						console.error('ERROR:', err);
						res.status(500).send("ko");
					});
			} else {
				// no message, return immediately
				res.status(200).send("[]");
			}
		});
	}
	return;
};
