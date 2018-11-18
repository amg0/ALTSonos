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
	
function listTopicSubscriptions(topicName) {
  // Creates a client
  const pubsub = new PubSub();

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
  // Creates a client
  const pubsub = new PubSub();

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
  // Creates a client
  const pubsub = new PubSub();

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

exports.veraPull = (req, res) => {	
	var client = new PubSub.v1.SubscriberClient({
	});
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
			returnImmediately: true
		};
		client
			.pull(request)
			.then(responses => {
				// The first element of `responses` is a PullResponse object.
				const response = responses[0];
				
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
					client
						.acknowledge(ackRequest)
						.then(not_used => {
							console.log('%d Messages acknowledged: ',ackRequest.ackIds.length,JSON.stringify(ackRequest.ackIds));
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
			.catch(err => {
				console.error('ERROR:', err);
				res.status(500).send("ko");
			});
	}
	return;
};
