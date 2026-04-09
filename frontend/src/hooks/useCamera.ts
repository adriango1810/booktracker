import { useState, useEffect, useRef, useCallback } from 'react';

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
    setCameraState(prev => ({ ...prev, isLoading: true, error: null }));
    
    try {
      const constraints = getOptimalConstraints();
      const stream = await navigator.mediaDevices.getUserMedia(constraints);
      
      streamRef.current = stream;
      
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play();
      }
      
      setCameraState({
        stream,
        isLoading: false,
        error: null,
        isReady: true,
      });
    } catch (error) {
      let errorMessage = 'Error al acceder a la cámara';
      
      if (error instanceof Error) {
        if (error.name === 'NotAllowedError') {
          errorMessage = 'Permiso de cámara denegado. Por favor, permite el acceso a la cámara.';
        } else if (error.name === 'NotFoundError') {
          errorMessage = 'No se encontró ninguna cámara en el dispositivo.';
        } else if (error.name === 'NotReadableError') {
          errorMessage = 'La cámara está siendo utilizada por otra aplicación.';
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
