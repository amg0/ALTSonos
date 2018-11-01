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

function listTopicSubscriptions(topicName) {
  // [START pubsub_list_topic_subscriptions]
  // Imports the Google Cloud client library
  const PubSub = require(`@google-cloud/pubsub`);

  // Creates a client
  const pubsub = new PubSub();

  /**
   * TODO(developer): Uncomment the following line to run the sample.
   */
  // const topicName = 'my-topic';

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
  // Imports the Google Cloud client library
  const PubSub = require(`@google-cloud/pubsub`);

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
  const PubSub = require(`@google-cloud/pubsub`);

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
	const PubSub = require(`@google-cloud/pubsub`);
	const PROJECT = 'altui-cloud-function'
	const topicname = 'sonos-event'
	const subscriptionname = 'vera-pull'
	
	var client = new PubSub.v1.SubscriberClient({
	  // optional auth parameters.
	});
	var formattedName = client.subscriptionPath(PROJECT, subscriptionname);
	var formattedTopic = client.topicPath(PROJECT, topicname);

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
			console.error('Subscription created:', subscriptionname);
			res.status(200).send("ok");
		  })
		  .catch(err => {
			console.error('ERROR:', err);
			res.status(500).send("ko");
		  });
	} else {
		// read a message
		const maxMessages = 10;
		const ackDeadlineSeconds = 30;
		const request = {
			subscription: formattedName,
			maxMessages: maxMessages,
			options: {
				timeout: 5	// 5 sec
			}
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
				response.receivedMessages.forEach(message => {
					ackRequest.ackIds.push(message.ackId);
					var buffer = Buffer.from(message.message.data)
					message.message.data = buffer.toString('ascii')
				});
				var result = response.receivedMessages;
				client
					.acknowledge(ackRequest)
					.then(not_used => {
						console.error('Messages acknowledged');
						res.status(200).send(JSON.stringify(result));
					})
					.catch(err => {
						console.error(err);
						res.status(500).send("ko");
					});
			})
			.catch(err => {
				console.error('ERROR:', err);
				res.status(500).send("ko");
			});
	}
	return;
};
