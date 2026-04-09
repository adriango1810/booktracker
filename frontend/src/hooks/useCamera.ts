import { useState, useEffect, useRef, useCallback } from 'react';
import { debugCamera, logVideoState } from '../utils/debug';

interface CameraState {
  stream: MediaStream | null;
  isLoading: boolean;
  error: string | null;
  isReady: boolean;
}

interface DeviceInfo {
  isIOS: boolean;
  isAndroid: boolean;
  isMobile: boolean;
}

export const useCamera = () => {
  const [cameraState, setCameraState] = useState<CameraState>({
    stream: null,
    isLoading: false,
    error: null,
    isReady: false,
  });

  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);

  const getDeviceInfo = useCallback((): DeviceInfo => {
    const userAgent = navigator.userAgent.toLowerCase();
    return {
      isIOS: /iphone|ipad|ipod/.test(userAgent),
      isAndroid: /android/.test(userAgent),
      isMobile: /iphone|ipad|ipod|android/.test(userAgent),
    };
  }, []);

  const getOptimalConstraints = useCallback(() => {
    const device = getDeviceInfo();
    
    if (device.isIOS) {
      return {
        video: {
          facingMode: 'environment',
          width: { ideal: 1280 },
          height: { ideal: 720 },
        },
        audio: false,
      };
    }
    
    if (device.isAndroid) {
      return {
        video: {
          facingMode: 'environment',
          width: { ideal: 1920 },
          height: { ideal: 1080 },
        },
        audio: false,
      };
    }
    
    return {
      video: {
        facingMode: 'environment',
        width: { ideal: 1280 },
        height: { ideal: 720 },
      },
      audio: false,
    };
  }, [getDeviceInfo]);

  const startCamera = useCallback(async () => {
    debugCamera();
    setCameraState(prev => ({ ...prev, isLoading: true, error: null }));
    
    try {
      const constraints = getOptimalConstraints();
      console.log('Requesting camera with constraints:', constraints);
      const stream = await navigator.mediaDevices.getUserMedia(constraints);
      
      console.log('Camera stream obtained:', {
        active: stream.active,
        tracks: stream.getTracks().length,
        trackStates: stream.getTracks().map(track => ({
          kind: track.kind,
          enabled: track.enabled,
          muted: track.muted,
          readyState: track.readyState
        }))
      });
      
      streamRef.current = stream;
      
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        
        // Wait for video to be ready to play
        await new Promise<void>((resolve, reject) => {
          const video = videoRef.current!;
          
          const handleCanPlay = () => {
            video.removeEventListener('canplay', handleCanPlay);
            video.removeEventListener('error', handleError);
            resolve();
          };
          
          const handleError = () => {
            video.removeEventListener('canplay', handleCanPlay);
            video.removeEventListener('error', handleError);
            reject(new Error('Video failed to load'));
          };
          
          video.addEventListener('canplay', handleCanPlay);
          video.addEventListener('error', handleError);
          
          // Fallback timeout
          setTimeout(() => {
            if (video.readyState >= 2) {
              handleCanPlay();
            } else {
              reject(new Error('Video load timeout'));
            }
          }, 5000);
        });
        
        try {
          await videoRef.current.play();
          console.log('Video play() successful');
          
          // Log video state after play
          logVideoState(videoRef.current);
        } catch (playError) {
          console.error('Video play() failed:', playError);
          throw new Error(`Video playback failed: ${playError instanceof Error ? playError.message : 'Unknown error'}`);
        }
      }
      
      setCameraState({
        stream,
        isLoading: false,
        error: null,
        isReady: true,
      });
    } catch (error) {
      console.error('Camera error:', error);
      let errorMessage = 'Error al acceder a la cámara';
      
      if (error instanceof Error) {
        console.error('Camera error details:', {
          name: error.name,
          message: error.message,
          stack: error.stack
        });
        
        if (error.name === 'NotAllowedError') {
          errorMessage = 'Permiso de cámara denegado. Por favor, permite el acceso a la cámara.';
        } else if (error.name === 'NotFoundError') {
          errorMessage = 'No se encontró ninguna cámara en el dispositivo.';
        } else if (error.name === 'NotReadableError') {
          errorMessage = 'La cámara está siendo utilizada por otra aplicación.';
        } else if (error.message.includes('Video load timeout')) {
          errorMessage = 'La cámara tardó demasiado en cargarse. Intenta recargar la página.';
        } else {
          errorMessage = `Error: ${error.message}`;
        }
      }
      
      setCameraState({
        stream: null,
        isLoading: false,
        error: errorMessage,
        isReady: false,
      });
    }
  }, [getOptimalConstraints]);

  const stopCamera = useCallback(() => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach(track => track.stop());
      streamRef.current = null;
    }
    
    if (videoRef.current) {
      videoRef.current.srcObject = null;
    }
    
    setCameraState({
      stream: null,
      isLoading: false,
      error: null,
      isReady: false,
    });
  }, []);

  useEffect(() => {
    return () => {
      stopCamera();
    };
  }, [stopCamera]);

  return {
    ...cameraState,
    videoRef,
    deviceInfo: getDeviceInfo(),
    startCamera,
    stopCamera,
  };
};
