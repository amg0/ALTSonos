# cd ALTSonos/
# chmod a+x install.sh
# echo $(DEVSHELL_PROJECT_ID)
cd $HOME
git clone https://github.com/amg0/ALTSonos/
cd ALTSonos/CloudFunction/
cd SonosEvent
gcloud functions deploy sonosEvent --trigger-http --memory=128 --region=europe-west1
cd ../VeraPull
gcloud functions deploy veraPull --trigger-http --memory=128 --region=europe-west1
cd ../SonosAuthorization
gcloud functions deploy sonosAuthorization --trigger-http --memory=128 --region=europe-west1
cd ..
