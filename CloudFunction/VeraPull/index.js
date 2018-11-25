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
const client = new PubSub.v1.SubscriberClient({ });

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

function tryDecrementCounter( relative ) {
	console.log("tryDecrementCounter: (%d)",relative)
	const transaction = datastore.transaction();
	var entity = null;
	return transaction
		.run()
		.then( () => transaction.get(key) )
		.then( results => {
			entity = results[0];
			if (entity) {
				console.log("tryDecrementCounter: counter value is %s",JSON.stringify(entity));
			}
			const newentity = {
				key: key,
				excludeFromIndexes: [
					'count'
				],
				data: {
					count: (entity) ? entity.count : 0
				}
			};
			newentity.data.count = Math.max( 0, newentity.data.count  - relative )
			transaction.save(newentity)
			console.log("tryDecrementCounter: set counter value to %s",JSON.stringify(newentity.data));
			return transaction.commit() 
		})
		.then(() => {
			// The transaction completed successfully.
			console.log('tryDecrementCounter: transaction updated properly');
		  })
		.catch( () => {
			console.log('tryDecrementCounter: Rolling back transaction');
			transaction.rollback()
		} )
}

function decrementCounter( relative ) {
	const maxTries = 5;
	let currentAttempt = 1;
	let delay = 100;

	function tryRequest() {
		return tryDecrementCounter( relative ).catch( err => {
			console.log('tryRequest: transaction failed, retry count:',currentAttempt);
			if (currentAttempt<= maxTries) {
				return new Promise( (resolve,reject) => {
					console.log('setting rety in %d ms',delay);
					setTimeout( ()=>{
						currentAttempt++;
						delay *= 2;
						tryRequest().then( resolve,reject );
					}, delay );
				});
			}
			console.log('tryRequest: Max rety count reached, transaction failed');
			return Promise.reject(err);
		});
	}
	return tryRequest();
}

async function createCounter() {
	console.log(`Creating new datastore entity for key ${key.path.join('/')}.`);
	const entity = {
		key: key,
		excludeFromIndexes: [
			'count'
		],
		data: {
			count: 0
		}
	};
	await datastore.insert(entity);
}

async function getCounter() {
	try {
		const [entity] = await datastore.get(key)
		if (!entity) {
			await createCounter();
			return 0
		}
		console.log("counter value is %s",JSON.stringify(entity));
		return entity.count
	}
	catch (err) {
		console.error(err);
		return null
	}
};

async function acknowledgeMessages(formattedName, response) {
	var result = [];
	const ackRequest = {
		subscription: formattedName,
		ackIds: [],
	};

	response.receivedMessages.forEach(message => {
		var buffer = Buffer.from(message.message.data);
		var item = {
			pubsubMessageId: message.message.messageId,
			data: JSON.parse(buffer.toString())
		};
		console.log( JSON.stringify(item.data) )
		ackRequest.ackIds.push(message.ackId);
		result.push(item);
	});

	if (ackRequest.ackIds.length > 0) {
		await client.acknowledge(ackRequest)	// will throw an exception in case of error, which will reject the async premise
		const idarray = result.map(m => m.pubsubMessageId);
		console.log('%d Messages acknowledged: ', idarray.length, JSON.stringify(idarray));
	}

	return result
}

async function initialize(formattedName, formattedTopic) {
	const request = {
		name: formattedName,
		topic: formattedTopic,
	};
	var responses = await client.createSubscription(request)
	var subscription = responses[0];
	console.log('Subscription created:', subscriptionname);
	await decrementCounter(0);	// create if required
	return responses
}

exports.veraPull = (req, res) => {	
	var formattedName = client.subscriptionPath(process.env.GCLOUD_PROJECT, subscriptionname);
	var formattedTopic = client.topicPath(process.env.GCLOUD_PROJECT, topicname);

	console.log( "headers:",JSON.stringify(req.headers));
	console.log( "body:",JSON.stringify(req.body) );
	
	if (req.query.init=='1') {
		initialize(formattedName, formattedTopic)
		.then(responses => {
			res.status(200).send("ok");
		})
		.catch(err => {
			console.error('ERROR:', err);
			res.status(500).send("ko, failed to create subscription " + subscriptionname);
		});
	} else {
		// read a message
		const maxMessages = 20;
		const request = {
			subscription: formattedName,
			maxMessages: maxMessages,
			returnImmediately: true,
		};

		getCounter()
		.then( count => {
			// return if no messages
			if (count && count > 0) {
				// messages , read pubsub
				client.pull(request)
				.then(responses => {
					// The first element of `responses` is a PullResponse object.
					const response = responses[0];
					var decrement = (response.receivedMessages.length>0) ? response.receivedMessages.length : count
					decrementCounter( decrement )
					.then ( () => {
						// Initialize `messages` with message ackId, message data and `false` as
						// processing state. Then, start each message in a worker function.
						acknowledgeMessages(formattedName, response)
						.then( result => {
							res.status(200).send(JSON.stringify(result));
						})
						.catch( err=>{
							console.error(err);
							res.status(500).send("ko");
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
		})
	}
	return;
};

