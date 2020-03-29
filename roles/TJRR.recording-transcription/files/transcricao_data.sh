#!/bin/bash
#/usr/local/sbin/transcricao_data.sh 2019-10-17 2019-11-01 | tee -a /var/log/bigbluebutton/transcribe/transcricao_data.log

if [ "x$1" == "x" ] ; then
  echo "Preencha a data inicial (inclusive) no formato aaaa-mm-dd. Ex.: 2019-10-17"
  exit
fi

if [ "x$2" == "x" ] ; then
  echo "Preencha a data final (exclusive) no formato aaaa-mm-dd. Ex.: 2019-10-17"
  exit
fi

data_inicio=$1
data_fim=$2
echo "`date` - hora de início"
for audiencia in `/usr/bin/find /var/bigbluebutton/published/presentation/ -maxdepth 1 -newermt $data_inicio -and -not -newermt $data_fim -ls | awk '{print $11}' | awk -F '/' '{print $6}'` ; do
  if [ -e "/var/bigbluebutton/published/presentation/$audiencia/video/webcams.mp4" ] ; then
    if [ ! -e "/var/bigbluebutton/published/presentation/$audiencia/caption_pt_BR.vtt" ] ; then
      echo "`date` - Rodando audiência $audiencia"
      sudo -u bigbluebutton ruby /usr/local/bigbluebutton/core/scripts/transcribe/transcribe.rb -m $audiencia --force 2>>/var/log/bigbluebutton/transcribe/transcricao_error.log
    else
      echo "`date` - Existe arquivo caption_pt_BR.vtt da audiência $audiencia"
    fi
  else
    echo "`date` - Audiência sem video/webcams.mp4 da audiência $audiencia"
  fi
done
echo "`date` - hora final"
