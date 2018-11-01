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
		var data = JSON.stringify(req.headers);
		const dataBuffer = Buffer.from(data)//.toString('base64');
		pubsub
			.topic('sonos-event')
			.publisher()
			.publish(dataBuffer)
			.then(messageId => {
			  console.log(`Message ${messageId} published.`);
			  res.status(200).send("ok - "+messageId);
			})
			.catch(err => {
				console.error('ERROR:', err);
				res.status(500).send("ko - failed to send message to topic:"+topicname);
			});
	}
	return
};
