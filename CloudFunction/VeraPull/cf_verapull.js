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

function createSubscription(topicName, subscriptionName) {
  // [START pubsub_create_pull_subscription]
  // Imports the Google Cloud client library
  const PubSub = require(`@google-cloud/pubsub`);

  // Creates a client
  const pubsub = new PubSub();

  /**
   * TODO(developer): Uncomment the following lines to run the sample.
   */
  // const topicName = 'my-topic';
  // const subscriptionName = 'my-sub';

  // Creates a new subscription
  pubsub
    .topic(topicName)
    .createSubscription(subscriptionName)
    .then(results => {
      const subscription = results[0];
      console.log(`Subscription ${subscriptionName} created.`);
    })
    .catch(err => {
      console.error('ERROR:', err);
    });
  // [END pubsub_create_pull_subscription]
}


exports.veraPullMessage = (req, res) => {
	// let code = req.query.code || req.body.code || '';
	// let state = req.query.state || req.body.state || '';
	// console.log({code:code, state:state})

	console.log( "headers:",JSON.stringify(req.headers));
	console.log( "body:",JSON.stringify(req.body) );

	res.status(200).send("ok");
};
