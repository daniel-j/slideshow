import sdl2_nim/sdl, sdl2_nim/sdl_image as image
import strutils, os, times, math
import easings
import ./perflogger

const imageDir = "images"
const transitionDuration = 1.5
const slideshowInterval = 8

{.passC: gorge("sdl2-config --cflags"), passL: gorge("sdl2-config --libs").}

var running = true

# make sure user has access to /dev/dri/renderD128 (add pi user to render group or run as root)

if not existsEnv("SDL_VIDEO_EGL_DRIVER"):
  putEnv("SDL_VIDEO_EGL_DRIVER", "libEGL.so")
if not existsEnv("SDL_VIDEO_GL_DRIVER"):
  putEnv("SDL_VIDEO_GL_DRIVER", "libGLESv2.so")

type
  Image = ref object of RootObj
    texture: sdl.Texture # Image texture
    w, h: int # Image dimensions

proc load(obj: var Image, renderer: sdl.Renderer, file: string): bool =
  result = true
  # Load image to texture
  obj.texture = renderer.loadTexture(file)
  if obj.texture == nil:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't load image %s: %s",
                    file, image.getError())
    return false
  # Get image dimensions
  var w, h: cint
  if obj.texture.queryTexture(nil, nil, addr(w), addr(h)) != 0:
    sdl.logCritical(sdl.LogCategoryError,
                    "Can't get texture attributes: %s",
                    sdl.getError())
    sdl.destroyTexture(obj.texture)
    return false
  # discard sdl.setTextureBlendMode(obj.texture, sdl.BLENDMODE_BLEND)
  obj.w = w
  obj.h = h

proc render(obj: Image, renderer: sdl.Renderer, x, y: int): bool =
  var rect = sdl.Rect(x: x, y: y, w: obj.w, h: obj.h)
  return renderer.renderCopy(obj.texture, nil, addr(rect)) == 0

type
  App = object
    window: sdl.Window
    renderer: sdl.Renderer
    windowWidth: int
    windowHeight: int
    images: seq[Image]
    start_time: Time
    startInterval: Time
    slide: int
    slidePosition: float
    progress: float
    progressY: float

proc events(app: var App): bool =
  result = true
  var ev: sdl.Event
  while sdl.pollEvent(ev.addr) != 0:
    if ev.kind == sdl.Quit:
      return false
    elif ev.kind == sdl.KeyDown:
      # Show what key was pressed
      sdl.logInfo(sdl.LogCategoryApplication, "Pressed %s", $ev.key.keysym.sym)

      # Exit on Escape key press
      if ev.key.keysym.sym == sdl.K_Escape or ev.key.keysym.sym == sdl.K_q:
        return false
    elif ev.kind == sdl.WindowEvent:
      var width, height: cint
      discard sdl.getRendererOutputSize(app.renderer, width.addr, height.addr)
      app.windowWidth = width
      app.windowHeight = height
      echo width, "x", height

proc contain(inw, inh, maxw, maxh: int): (int, int) =
  let ratio = inw.float / inh.float
  result[0] = maxw
  result[1] = maxh
  if maxw/maxh > ratio:
    result[0] = int(maxh.float * ratio)
  else:
    result[1] = int(maxw.float / ratio)

proc update(app: var App): bool =
  result = true
  let now = getTime()
  let intervalElapsed = (now - app.startInterval).inMilliseconds().float / 1000.0
  
  if intervalElapsed >= slideshowInterval - transitionDuration:
    if intervalElapsed < slideshowInterval:
      let offset = intervalElapsed - slideshowInterval + transitionDuration
      app.slidePosition = easingsInOutCubic(offset / transitionDuration.float)
      app.progressY = 1.0 - (offset / transitionDuration.float) * 2.0
    else:
      app.startInterval = now
      app.slidePosition = 0
      inc(app.slide)
      if app.slide >= len(app.images):
        app.slide = 0
  else:
    app.progress = easingsLinear(intervalElapsed / (slideshowInterval - transitionDuration))
    app.progressY = 1.0


proc clear(app: App) =
  discard app.renderer.setRenderDrawColor(0x00, 0x00, 0x00, sdl.ALPHA_OPAQUE)
  discard app.renderer.renderClear()

proc render(app: App): bool =
  result = true

  app.clear()

  # discard app.renderer.setRenderDrawColor(0xFF, 0x00, 0x00, sdl.ALPHA_OPAQUE)
  var r = sdl.Rect(x: 0, y: 0, w: 1, h: 1)


  var img = app.images[app.slide]
  (r.w, r.h) = contain(img.w, img.h, app.windowWidth, app.windowHeight)
  r.x = floor((app.windowWidth.float / 2.0) - (r.w.float / 2.0) - app.slidePosition * app.windowWidth.float * 1.1).int
  r.y = 0
  # discard sdl.setTextureAlphaMod(img.texture, counter.uint8)
  discard app.renderer.renderCopy(img.texture, nil, r.addr)

  var nextslide = app.slide + 1
  if nextslide >= len(app.images): nextslide = 0
  if app.slide != nextslide:
    var img = app.images[nextslide]
    (r.w, r.h) = contain(img.w, img.h, app.windowWidth, app.windowHeight)
    r.x = floor((app.windowWidth.float / 2.0) - (r.w.float / 2.0) + (app.windowWidth.float * 1.1) - app.slidePosition * app.windowWidth.float * 1.1).int
    r.y = 0
    # discard sdl.setTextureAlphaMod(img.texture, counter.uint8)
    discard app.renderer.renderCopy(img.texture, nil, r.addr)

  discard app.renderer.setRenderDrawColor(0x44, 0x44, 0x44, (192.float * app.progressY).uint8)
  var r2 = sdl.Rect(x: 0, y: ceil(app.windowHeight.float - 0.01 * app.windowHeight.float * app.progressY).int, w: floor(app.windowWidth.float * app.progress).int, h: int(0.01 * app.windowHeight.float))
  discard app.renderer.renderFillRect(r2.addr)

  app.renderer.renderPresent()
  fps_logger()

proc start(app: var App) =
  if sdl.init(0) != 0:
    sdl.logCritical(sdl.LogCategoryError, "Can't initialize SDL: %s", sdl.getError())
    return
  defer: sdl.quit()
  if image.init(image.INIT_JPG or image.INIT_PNG) == 0:
    sdl.logCritical(sdl.LogCategoryError, "Can't initialize SDL_image: %s", image.getError())
    return
  defer: image.quit()
  
  let numDrivers = sdl.getNumVideoDrivers()
  var drivers = newSeq[bool](numDrivers)
  var driverNames = newSeq[string](numDrivers)
  for i in 0..<len(drivers):
    let name = sdl.getVideoDriver(i.cint)
    drivers[i] = sdl.videoInit(name) == 0
    driverNames[i] = $name
    sdl.videoQuit()
  
  # echo sdl.setHint(sdl.HINT_RENDER_DRIVER, "opengles2")
  discard sdl.setHint(sdl.HINT_VIDEO_DOUBLE_BUFFER, "1")
  
  echo "SDL_VIDEODRIVER available  : ", driverNames.join(" ")

  var usableDrivers: seq[string]
  for i in 0..<len(drivers):
    if not drivers[ i ]:
      continue
    usableDrivers.add(driverNames[i])
  
  echo "SDL_VIDEODRIVER usable     : ", usableDrivers.join(" ")
  
  if sdl.init(sdl.INIT_VIDEO) != 0:
    sdl.logCritical(sdl.LogCategoryError, "Can't initialize SDL: %s", sdl.getError())
    return

  #discard sdl.glSetAttribute(sdl.GL_CONTEXT_PROFILE_MASK, sdl.GL_CONTEXT_PROFILE_ES);
  echo sdl.getHint(sdl.HINT_RENDER_DRIVER)

  echo "SDL_VIDEODRIVER selected   : ", sdl.getCurrentVideoDriver()

  discard sdl.showCursor(false.cint)

  var renderDrivers = newSeq[string](sdl.getNumRenderDrivers())
  for i in 0..<len(renderDrivers):
    var info: sdl.RendererInfo
    discard sdl.getRenderDriverInfo(i.cint, info.addr)
    renderDrivers[i] = $info.name
  echo "SDL_RENDER_DRIVER available: ", renderDrivers.join(" ")

  var dm: sdl.DisplayMode
  if sdl.getDesktopDisplayMode(0, dm.addr) != 0:
    sdl.logCritical(sdl.LogCategoryError, "GetDesktopDisplayMode failed: %s", sdl.getError())
    return

  app.window = sdl.createWindow(
    "Slideshow",
    sdl.WINDOWPOS_UNDEFINED, sdl.WINDOWPOS_UNDEFINED,
    dm.w, dm.h,
    sdl.WINDOW_FULLSCREEN_DESKTOP or sdl.WINDOW_SHOWN
  )
  if app.window.isNil:
    sdl.logCritical(sdl.LogCategoryError, "Can't create window: %s", sdl.getError())
    return
  defer: sdl.destroyWindow(app.window)

  app.renderer = sdl.createRenderer(app.window, -1, sdl.RENDERER_ACCELERATED or sdl.RENDERER_PRESENTVSYNC)
  if app.renderer.isNil:
    sdl.logCritical(sdl.LogCategoryError, "Can't create renderer: %s", sdl.getError())
    return
  defer: sdl.destroyRenderer(app.renderer)

  var info: sdl.RendererInfo
  discard sdl.getRendererInfo(app.renderer, info.addr)
  echo "SDL_RENDER_DRIVER selected : ", info.name, " (flags: ", info.flags, ")"

  discard sdl.setRenderDrawBlendMode(app.renderer, sdl.BLENDMODE_BLEND)


  # Set draw color
  if app.renderer.setRenderDrawColor(0x00, 0x00, 0x00, 0xFF) != 0:
    sdl.logWarn(sdl.LogCategoryVideo, "Can't set draw color: %s", sdl.getError())

  for kind, path in walkDir(imageDir):
    echo kind, " ", path
    var img = Image()
    if img.load(app.renderer, path):
      app.images.add(img)

  initPerflogger()
  defer: endPerflogger()
  setControlCHook(proc () {.noconv.} =
    echo "Stopping..."
    running = false
    unsetControlCHook()
  )
  defer: unsetControlCHook()
  app.start_time = getTime()
  app.startInterval = getTime()
  while app.events() and app.update() and app.render() and running:
    discard
  

when isMainModule:
  var app = App()
  app.start()
