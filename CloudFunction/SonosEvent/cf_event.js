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


function listAllTopics() {
  // [START pubsub_list_topics]
  // Imports the Google Cloud client library
  const PubSub = require(`@google-cloud/pubsub`);

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

function createTopic(topicName) {
	// Creates a client
	const pubsub = new PubSub();

	// Creates a new topic
	pubsub
		.createTopic(topicName)
		.then(results => {
		  const topic = results[0];
		  console.log(`Topic ${topicName} created.`);
		})
		.catch(err => {
		  console.error('ERROR:', err);
		});
	return;
}

function publishMessage(topicName, data) {
	// Creates a client
	const pubsub = new PubSub();

	// Publishes the message as a string, e.g. "Hello, world!" or JSON.stringify(someObject)
	const dataBuffer = Buffer.from(data);

	pubsub
		.topic(topicName)
		.publisher()
		.publish(dataBuffer)
		.then(messageId => {
		  console.log(`Message ${messageId} published.`);
		})
		.catch(err => {
		  console.error('ERROR:', err);
		  return 0;
		});
	return 1;
}

exports.sonosEventCallback = (req, res) => {
	// let code = req.query.code || req.body.code || '';
	// let state = req.query.state || req.body.state || '';
	// console.log({code:code, state:state})

	console.log( "headers:",JSON.stringify(req.headers));
	console.log( "body:",JSON.stringify(req.body) );

	if (publishMessage('sonos-event', JSON.stringify(req.headers)) ==0) {
		res.status(500).send("ko");
		return
	}
	res.status(200).send("ok");
};
