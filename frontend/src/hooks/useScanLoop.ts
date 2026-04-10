import { useState, useEffect, useRef, useCallback } from 'react';

interface ScanLoopState {
  isScanning: boolean;
  fps: number;
  frameCount: number;
  lastFrameTime: number;
}

interface DeviceInfo {
  isIOS: boolean;
  isAndroid: boolean;
  isMobile: boolean;
}

interface ROI {
  x: number;
  y: number;
  width: number;
  height: number;
}

export const useScanLoop = (
  videoRef: React.RefObject<HTMLVideoElement | null>,
  deviceInfo: DeviceInfo,
  isReady: boolean
) => {
  // Configuración parametrizable con variables de entorno
  const ROI_RATIO = parseFloat(import.meta.env.VITE_SCAN_ROI_RATIO || '0.65'); // Ligeramente aumentado de 0.6 a 0.65
  const FPS_IOS = parseInt(import.meta.env.VITE_SCAN_FPS_IOS || '2');
  const FPS_ANDROID = parseInt(import.meta.env.VITE_SCAN_FPS_ANDROID || '4');
  const FPS_DESKTOP = 3;
  
  // Comentario sobre ROI: Un ROI demasiado pequeño puede recortar parcialmente el código de barras,
  // mientras que uno demasiado grande reduce la densidad de píxeles por barra, dificultando la detección.
  // El valor 0.65 busca un balance entre capturar suficiente contexto y mantener buena densidad de píxeles.
  
  const [scanState, setScanState] = useState<ScanLoopState>({
    isScanning: false,
    fps: deviceInfo.isIOS ? FPS_IOS : deviceInfo.isAndroid ? FPS_ANDROID : FPS_DESKTOP,
    frameCount: 0,
    lastFrameTime: 0,
  });

  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animationRef = useRef<number | null>(null);
  const scanCallbackRef = useRef<((imageData: ImageData) => void) | null>(null);

  const getROI = useCallback((): ROI => {
    if (!videoRef.current) return { x: 0, y: 0, width: 0, height: 0 };
    
    const video = videoRef.current;
    const videoWidth = video.videoWidth;
    const videoHeight = video.videoHeight;
    
    // Para video vertical (como en Android), usar el ancho como base
    const roiSize = Math.min(videoWidth, videoHeight) * ROI_RATIO;
    const x = (videoWidth - roiSize) / 2;
    const y = (videoHeight - roiSize) / 2;
    
    const roi = {
      x: Math.round(x),
      y: Math.round(y),
      width: Math.round(roiSize),
      height: Math.round(roiSize),
    };
    
    return roi;
  }, [videoRef, ROI_RATIO]);

  const captureFrame = useCallback((): ImageData | null => {
    if (!videoRef.current || !canvasRef.current || !isReady) {
      return null;
    }
    
    const video = videoRef.current;
    const canvas = canvasRef.current;
    const ctx = canvas.getContext('2d');
    
    if (!ctx) {
      return null;
    }
    
    if (video.readyState !== 4) {
      return null;
    }
    
    if (video.videoWidth === 0 || video.videoHeight === 0) {
      return null;
    }
    
    const roi = getROI();
    
    canvas.width = roi.width;
    canvas.height = roi.height;
    
    ctx.drawImage(
      video,
      roi.x,
      roi.y,
      roi.width,
      roi.height,
      0,
      0,
      roi.width,
      roi.height
    );
    
    const imageData = ctx.getImageData(0, 0, roi.width, roi.height);
    
    return imageData;
  }, [videoRef, isReady, getROI]);

  const scanLoop = useCallback((timestamp: number) => {
    if (!scanState.isScanning) {
      return;
    }
    
    const frameInterval = 1000 / scanState.fps;
    const timeSinceLastFrame = timestamp - scanState.lastFrameTime;
    
    if (timeSinceLastFrame >= frameInterval) {
      const imageData = captureFrame();
      
      if (imageData && scanCallbackRef.current) {
        // Log cada 100 frames para no saturar (reducido de 50)
        if (scanState.frameCount % 100 === 0) {
          console.log('?? Frame processed:', {
            frameCount: scanState.frameCount,
            size: `${imageData.width}x${imageData.height}`
          });
        }
        
        scanCallbackRef.current(imageData);
        
        setScanState(prev => ({
          ...prev,
          frameCount: prev.frameCount + 1,
          lastFrameTime: timestamp,
        }));
      } else {
        // Update lastFrameTime even if capture failed to prevent spam
        setScanState(prev => ({
          ...prev,
          lastFrameTime: timestamp,
        }));
      }
    }
    
    if (scanState.isScanning) {
      animationRef.current = requestAnimationFrame(scanLoop);
    }
  }, [scanState.isScanning, scanState.fps, scanState.lastFrameTime, captureFrame]);

  const startScanning = useCallback((callback: (imageData: ImageData) => void) => {
    if (!isReady) return;
    
    // Stop any existing scanning first
    if (animationRef.current) {
      cancelAnimationFrame(animationRef.current);
      animationRef.current = null;
    }
    
    scanCallbackRef.current = callback;
    setScanState(prev => ({ 
      ...prev, 
      isScanning: true,
      lastFrameTime: performance.now()
    }));
  }, [isReady]);

  const stopScanning = useCallback(() => {
    setScanState(prev => ({ ...prev, isScanning: false }));
    
    if (animationRef.current) {
      cancelAnimationFrame(animationRef.current);
      animationRef.current = null;
    }
    
    scanCallbackRef.current = null;
  }, []);

  const updateFPS = useCallback((newFPS: number) => {
    setScanState(prev => ({ ...prev, fps: newFPS }));
  }, []);

  useEffect(() => {
    if (scanState.isScanning && isReady && !animationRef.current) {
      animationRef.current = requestAnimationFrame(scanLoop);
    }
    
    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
        animationRef.current = null;
      }
    };
  }, [scanState.isScanning, isReady, scanLoop]);

  return {
    ...scanState,
    canvasRef,
    startScanning,
    stopScanning,
    updateFPS,
    getROI,
  };
};
