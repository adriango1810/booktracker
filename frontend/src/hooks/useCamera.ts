import { useState, useEffect, useRef, useCallback } from 'react';
import { debugCamera } from '../utils/debug';

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

export const useCamera = (videoRef: React.RefObject<HTMLVideoElement | null>) => {
  const [cameraState, setCameraState] = useState<CameraState>({
    stream: null,
    isLoading: false,
    error: null,
    isReady: false,
  });

  const streamRef = useRef<MediaStream | null>(null);

  const getDeviceInfo = useCallback((): DeviceInfo => {
    const userAgent = navigator.userAgent.toLowerCase();
    return {
      isIOS: /iphone|ipad|ipod/.test(userAgent),
      isAndroid: /android/.test(userAgent),
      isMobile: /iphone|ipad|ipod|android/.test(userAgent),
    };
  }, []);

  const getOptimalConstraints = useCallback(async () => {
    // Constraints de alta calidad - objetivo 1920x1080
    const highConstraints = {
      video: {
        facingMode: 'environment',
        width: { ideal: 1920, min: 640 },
        height: { ideal: 1080, min: 480 },
      },
      audio: false,
    };
    
    // Constraints de fallback - más relajadas
    const fallbackConstraints = {
      video: {
        facingMode: 'environment',
        width: { ideal: 1280 },
        height: { ideal: 720 },
      },
      audio: false,
    };
    
    try {
      // Intentar primero con alta calidad
      const stream = await navigator.mediaDevices.getUserMedia(highConstraints);
      stream.getTracks().forEach(track => track.stop()); // Liberar stream de prueba
      return highConstraints;
    } catch (error) {
      console.log('High quality constraints not supported, using fallback:', error);
      return fallbackConstraints;
    }
  }, []);

  const startCamera = useCallback(async () => {
    debugCamera();
    setCameraState(prev => ({ ...prev, isLoading: true, error: null }));
    
    try {
      const constraints = await getOptimalConstraints();
      const stream = await navigator.mediaDevices.getUserMedia(constraints);
      
      streamRef.current = stream;
      
      // Esperar a que videoRef esté disponible
      let attempts = 0;
      while (!videoRef.current && attempts < 50) {
        await new Promise(resolve => setTimeout(resolve, 100));
        attempts++;
      }
      
      if (videoRef.current) {
        // Configurar atributos del video ANTES de asignar stream
        videoRef.current.setAttribute('playsinline', 'true');
        videoRef.current.setAttribute('muted', 'true');
        videoRef.current.style.width = '100%';
        videoRef.current.style.height = '100%';
        
        // Asignar stream al video
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
        } catch (playError) {
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
    deviceInfo: getDeviceInfo(),
    startCamera,
    stopCamera,
  };
};
