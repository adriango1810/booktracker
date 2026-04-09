export const debugCamera = () => {
  console.group('📷 Camera Debug Info');
  
  // Browser info
  console.log('User Agent:', navigator.userAgent);
  console.log('Platform:', navigator.platform);
  
  // Media devices support
  console.log('Media Devices Support:', 'mediaDevices' in navigator);
  console.log('Get User Media Support:', 'getUserMedia' in (navigator.mediaDevices || {}));
  
  // Screen info
  console.log('Screen:', {
    width: screen.width,
    height: screen.height,
    availWidth: screen.availWidth,
    availHeight: screen.availHeight,
    colorDepth: screen.colorDepth,
    pixelDepth: screen.pixelDepth
  });
  
  // Viewport
  console.log('Viewport:', {
    width: window.innerWidth,
    height: window.innerHeight,
    devicePixelRatio: window.devicePixelRatio
  });
  
  // Video element capabilities
  const video = document.createElement('video');
  console.log('Video capabilities:', {
    canPlayType: typeof video.canPlayType,
    playsInline: 'playsInline' in video,
    autoplay: 'autoplay' in video,
    muted: 'muted' in video
  });
  
  console.groupEnd();
};

export const logVideoState = (video: HTMLVideoElement | null) => {
  if (!video) {
    console.log('❌ No video element');
    return;
  }
  
  console.group('🎥 Video State');
  console.log('Ready State:', video.readyState, '(', {
    0: 'HAVE_NOTHING',
    1: 'HAVE_METADATA', 
    2: 'HAVE_CURRENT_DATA',
    3: 'HAVE_FUTURE_DATA',
    4: 'HAVE_ENOUGH_DATA'
  }[video.readyState], ')');
  
  console.log('Network State:', video.networkState, '(', {
    0: 'NETWORK_EMPTY',
    1: 'NETWORK_IDLE',
    2: 'NETWORK_LOADING',
    3: 'NETWORK_NO_SOURCE'
  }[video.networkState], ')');
  
  console.log('Dimensions:', {
    videoWidth: video.videoWidth,
    videoHeight: video.videoHeight,
    width: video.width,
    height: video.height
  });
  
  console.log('Stream:', !!video.srcObject);
  console.log('Paused:', video.paused);
  console.log('Ended:', video.ended);
  console.log('Muted:', video.muted);
  console.log('Controls:', video.controls);
  
  console.groupEnd();
};
