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
  const [scanState, setScanState] = useState<ScanLoopState>({
    isScanning: false,
    fps: deviceInfo.isIOS ? 2 : deviceInfo.isAndroid ? 4 : 3,
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
    
    const roiSize = Math.min(videoWidth, videoHeight) * 0.6;
    const x = (videoWidth - roiSize) / 2;
    const y = (videoHeight - roiSize) / 2;
    
    return {
      x: Math.round(x),
      y: Math.round(y),
      width: Math.round(roiSize),
      height: Math.round(roiSize),
    };
  }, [videoRef]);

  const captureFrame = useCallback((): ImageData | null => {
    if (!videoRef.current || !canvasRef.current || !isReady) {
      console.log('Capture frame blocked:', { 
        hasVideo: !!videoRef.current, 
        hasCanvas: !!canvasRef.current, 
        isReady,
        videoReadyState: videoRef.current?.readyState
      });
      return null;
    }
    
    const video = videoRef.current;
    const canvas = canvasRef.current;
    const ctx = canvas.getContext('2d');
    
    if (!ctx || video.readyState !== 4) {
      console.log('Capture frame failed:', { 
        hasContext: !!ctx, 
        readyState: video.readyState,
        videoWidth: video.videoWidth,
        videoHeight: video.videoHeight
      });
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
    
    return ctx.getImageData(0, 0, roi.width, roi.height);
  }, [videoRef, isReady, getROI]);

  const scanLoop = useCallback((timestamp: number) => {
    if (!scanState.isScanning) {
      console.log('Scan loop: not scanning, exiting');
      return;
    }
    
    const frameInterval = 1000 / scanState.fps;
    const timeSinceLastFrame = timestamp - scanState.lastFrameTime;
    
    if (timeSinceLastFrame >= frameInterval) {
      const imageData = captureFrame();
      
      if (imageData && scanCallbackRef.current) {
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
    console.log('startScanning called:', { isReady });
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
    
    console.log('Scanning started, isScanning set to true');
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
    console.log('ScanLoop useEffect:', { 
      isScanning: scanState.isScanning, 
      isReady, 
      hasAnimationRef: !!animationRef.current 
    });
    
    if (scanState.isScanning && isReady && !animationRef.current) {
      console.log('Starting animation frame loop');
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
