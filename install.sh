#!/bin/bash

# Do these steps first manually from the console shell
# rm -rf ALTSonos
# git clone https://github.com/amg0/ALTSonos/
# cd ALTSonos/
# chmod a+x install.sh

# export MYREGION = "europe-west1"
# export MYPROJECT = "altui-cloud-function"

cd ~/ALTSonos/CloudFunction/SonosEvent
gcloud functions deploy sonosEvent --trigger-http --memory=128 --region=$MYREGION

cd ../VeraPull
gcloud functions deploy veraPull --trigger-http --memory=128 --region=$MYREGION

cd ../SonosAuthorization
gcloud functions deploy sonosAuthorization --trigger-http --memory=128 --region=$MYREGION

cd ..
curl https://$MYREGION-$MYPROJECT.cloudfunctions.net/sonosEvent?init=1
curl https://$MYREGION-$MYPROJECT.cloudfunctions.net/veraPull?init=1
