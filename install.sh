#!/bin/bash
# cd ALTSonos/
# chmod a+x install.sh
# echo $(DEVSHELL_PROJECT_ID)
# git clone https://github.com/amg0/ALTSonos/

cd ALTSonos/CloudFunction/SonosEvent
gcloud functions deploy sonosEvent --trigger-http --memory=128 --region=$MYREGION
cd ../VeraPull
gcloud functions deploy veraPull --trigger-http --memory=128 --region=$MYREGION
cd ../SonosAuthorization
gcloud functions deploy sonosAuthorization --trigger-http --memory=128 --region=$MYREGION
cd ..

curl https://europe-west1-altui-cloud-function.cloudfunctions.net/sonosEvent?init=1
curl https://europe-west1-altui-cloud-function.cloudfunctions.net/veraPull?init=1
