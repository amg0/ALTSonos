#!/bin/bash

# Do these steps first manually from the console shell
# rm -rf ALTSonos
# git clone https://github.com/amg0/ALTSonos/
# cd ALTSonos/
# chmod a+x install.sh

# export MYREGION = "my region"
# export MYPROJECT = "my project id"

cd ~/ALTSonos/CloudFunction/SonosEvent
gcloud functions deploy sonosEvent --runtime nodejs8 --trigger-http --memory=256 --region=$MYREGION

cd ../VeraPull
gcloud functions deploy veraPull --runtime nodejs8 --trigger-http --memory=256 --region=$MYREGION

cd ../SonosAuthorization
gcloud functions deploy sonosAuthorization --runtime nodejs8 --trigger-http --memory=128 --region=$MYREGION

cd ..
curl https://$MYREGION-$MYPROJECT.cloudfunctions.net/sonosEvent?init=1
curl https://$MYREGION-$MYPROJECT.cloudfunctions.net/veraPull?init=1
