#!/bin/bash

start(){

  cleanup

  start_container

}

cleanup(){
  #Delete any previous report file
  rm -rf ffmpeg*.log
  rm -rf *.json
}

start_container(){

  if ! $(docker inspect jellyfin | jq -r '.[].State.Running'); then
    docker run --rm -it -d --name jellyfin --device=/dev/dri:/dev/dri -v $(pwd):/config jellyfin/jellyfin
  fi

  sleep 5s

  if $(docker inspect jellyfin | jq -r '.[].State.Running'); then
    main
  else
    echo "Jellyfin container not running"
    exit 127
  fi

}

stop_container(){

  if $(docker inspect jellyfin | jq -r '.[].State.Running'); then
    docker stop jellyfin > /dev/null
    docker rmi jellyfin/jellyfin > /dev/null
  fi

}

benchmarks(){

  intel_gpu_top -s 100ms -J -o $1.json &
  igtpid=$(echo $!)
  docker exec -it jellyfin /config/benchmark.sh $1
  kill -s SIGINT $igtpid

  #Add brackets to beginning and end of json output to make valid json
  sed -i '1s/^/[\n/' $1.json
  echo ']' >> $1.json

  #Calculate average Wattage
  total_watts=$(jq -r '.[]."power"."GPU"' $1.json | grep -Ev '^0' | paste -s -d + - | bc)
  total_count=$(jq -r '.[]."power"."GPU"' $1.json | grep -Ev '^0' | wc -l)
  avg_watts=$(echo "scale=2; $total_watts / $total_count" | bc -l)

  for i in $(ls ffmpeg-*.log); do 
    #Calculate average FPS
    total_fps=$(grep -Eo 'fps= [1-9].' $i | sed -e 's/fps= //' | paste -s -d + - | bc)
    fps_count=$(grep -Eo 'fps= [1-9].' $i | wc -l)
    avg_fps=$(echo "scale=2; $total_fps / $fps_count" | bc -l)

    #Calculate average speed
    total_speed=$(grep -Eo 'speed=[0-9].[0-9].' $i | sed -e 's/speed=//' | paste -s -d + - | bc)
    speed_count=$(grep -Eo 'speed=[0-9].[0-9].' $i | sed -e 's/speed=//' | wc -l)
    avg_speed="$(echo "scale=2; $total_speed / $speed_count" | bc -l)x"

    #Get Bitrate of file
    bitrate=$(grep -Eo 'bitrate: [1-9].*' $i | sed -e 's/bitrate: //')

    #Get time to convert
    total_time=$(grep -Eo 'rtime=[1-9].*s' $i | sed -e 's/rtime=//')

    #delete log file
    rm -rf $i
  done

  #Add data to array
  quicksyncstats_arr+=("$cpu_model|$2|$bitrate|$total_time|$avg_fps|$avg_speed|$avg_watts")

  rm -rf $1.json

}

main(){

  #Sets Array
  quicksyncstats_arr=("CPU|FILE|BITRATE|TIME|AVG_FPS|AVG_SPEED|AVG_WATTS")

  #Collections CPU Model
  cpu_model=$(cat /proc/cpuinfo | grep -m1 'model name' | awk '{ print $6 }')

  benchmarks h264_1080p ribblehead_1080p_h264

  benchmarks h264_4k ribblehead_4k_h264

  benchmarks hevc_8bit ribblehead_1080p_hevc_8bit

  benchmarks hevc_4k_10bit ribblehead_4k_hevc_10bit

  #Print Results
  printf '%s\n' "${quicksyncstats_arr[@]}" | column -t -s '|'
  printf "\n"

  #Unset Array
  unset quicksyncstats_arr

  stop_container

}

start