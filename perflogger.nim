import times

var prev_utime: Time
var tot_frames, frames: uint64
var prev_time: int64
var avg_frametime: Duration
var start_utime: Time

proc endPerflogger*() =
  let end_utime = getTime()
  let tot_time = (end_utime - start_utime).inMilliseconds().float / 1000.0

  echo "Frames\t Time\t Avg. FPS"
  echo tot_frames, "\t ", tot_time, "s\t ", tot_frames.float / tot_time.float

proc fps_logger*() =
  inc(tot_frames)
  inc(frames)

  let cur_utime = getTime()
  let cur_time = cur_utime.toUnix()

  avg_frametime = avg_frametime + (cur_utime - prev_utime)

  prev_utime = cur_utime

  if cur_time > prev_time:
    prev_time = cur_time
    echo "FPS: ", frames, "  \t Avg. frametime: ", (avg_frametime.inMicroseconds.uint64 div frames).float / 1000.0, " ms"
    avg_frametime = DurationZero
    frames = 0

proc initPerflogger*() =
  start_utime = getTime()
  prev_utime = getTime()

  echo "Perflogger starting.."
