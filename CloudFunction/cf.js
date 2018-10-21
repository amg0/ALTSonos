/**
 * Responds to any HTTP request.
 *
 * @param {!express:Request} req HTTP request context.
 * @param {!express:Response} res HTTP response context.
 */

//https://192.168.1.17/port_3480/data_request?id=lr_DENON_Handler&command=AuthorizationCB&DeviceNum=264
//https://192.168.1.17/port_3480/data_request?id=lr_DENON_Handler&command=EventCB&DeviceNum=264s

exports.sonosCallback = (req, res) => {
  let code = req.query.code || req.body.code || '';
  let state = req.query.state || req.body.state || '';
  console.log({code:code, state:state})
  try {
    state = JSON.parse( Buffer.from(state, 'base64').toString() )
    let url = "http://"+state.ip+"/port_3480/data_request?id=lr_ALTSonos_Handler&command=AuthorizationCB&DeviceNum="+state.devnum+"&code="+code
    res.redirect(url)
  }
  catch(error) {
    console.error(error);
    res.status(500).send('an error happened in google cloud function while decoding the state parameter');
  }
};
