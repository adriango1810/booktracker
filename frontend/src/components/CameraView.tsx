import React, { useEffect, useRef, useCallback } from 'react';
import { useCamera } from '../hooks/useCamera';
import { useScanLoop } from '../hooks/useScanLoop';
import { useISBNReader } from '../hooks/useISBNReader';

interface CameraViewProps {
  onFrameCapture?: (imageData: ImageData) => void;
  onISBNDetected?: (isbn: string) => void;
  className?: string;
}

export const CameraView: React.FC<CameraViewProps> = ({ 
  onFrameCapture, 
  onISBNDetected,
  className = '' 
}) => {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  
  const {
    isReading,
    lastISBN,
    detectionHistory,
    processFrame: processISBNFrame,
  } = useISBNReader({ onISBNDetected });
  
  const {
    isLoading,
    error,
    isReady,
    deviceInfo,
    startCamera,
    stopCamera,
  } = useCamera(videoRef);

  const {
    isScanning,
    fps,
    frameCount,
    canvasRef,
    startScanning,
    stopScanning,
    getROI,
  } = useScanLoop(videoRef, deviceInfo, isReady);

  useEffect(() => {
    // Esperar a que el componente se monte completamente
    const timer = setTimeout(() => {
      console.log('Component mounted, starting camera...');
      startCamera();
    }, 100);
    
    return () => {
      clearTimeout(timer);
      stopCamera();
    };
  }, [startCamera, stopCamera]);

  // Callback combinado para frame capture y detección ISBN
  const handleFrameCapture = useCallback(async (imageData: ImageData) => {
    // Procesar frame para detección de ISBN
    await processISBNFrame(imageData);
    
    // Llamar al callback original si existe
    if (onFrameCapture) {
      onFrameCapture(imageData);
    }
  }, [processISBNFrame, onFrameCapture]);

  useEffect(() => {
    console.log('CameraView useEffect:', { isReady, hasCallback: !!onFrameCapture });
    
    // Activar escaneo ahora que la cámara funciona
    if (isReady && onFrameCapture) {
      console.log('Starting scanning...');
      startScanning(handleFrameCapture!);
    } else {
      console.log('Scanning paused - checking initialization logs');
      stopScanning();
    }
    
    return () => stopScanning();
  }, [isReady, onFrameCapture, startScanning, stopScanning, handleFrameCapture]);

  const roi = getROI();

  if (error) {
    return (
      <div className={`camera-error ${className}`}>
        <div className="error-message">
          <h3>Error de cámara</h3>
          <p>{error}</p>
          <button onClick={startCamera} className="retry-button">
            Reintentar
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className={`camera-view ${className}`}>
      <video
        ref={videoRef}
        className="camera-video"
        playsInline
        muted
        autoPlay
      />
      
      <canvas
        ref={canvasRef}
        className="scan-canvas"
        style={{ display: 'none' }}
      />
      
      {isLoading && (
        <div className="loading-overlay">
          <div className="loading-spinner">
            <div className="spinner"></div>
            <p>Inicializando cámara...</p>
          </div>
        </div>
      )}
      
      {roi.width > 0 && roi.height > 0 && (
        <div className="scan-overlay">
          <div 
            className="roi-frame"
            style={{
              left: `${(roi.x / (videoRef.current?.videoWidth || 1)) * 100}%`,
              top: `${(roi.y / (videoRef.current?.videoHeight || 1)) * 100}%`,
              width: `${(roi.width / (videoRef.current?.videoWidth || 1)) * 100}%`,
              height: `${(roi.height / (videoRef.current?.videoHeight || 1)) * 100}%`,
            }}
          >
            <div className="corner corner-tl"></div>
            <div className="corner corner-tr"></div>
            <div className="corner corner-bl"></div>
            <div className="corner corner-br"></div>
          </div>
        </div>
      )}
      
      <div className="scan-info">
        <div className="status-indicator">
          <div className={`status-dot ${isScanning ? 'scanning' : 'idle'} ${isReading ? 'reading' : ''}`}></div>
          <span className="status-text">
            {isReading ? 'Detectando ISBN...' : isScanning ? 'Escaneando...' : 'Cámara lista'}
          </span>
        </div>
        
        <div className="scan-stats">
          <span>FPS: {fps}</span>
          <span>Frames: {frameCount}</span>
          <span>Dispositivo: {deviceInfo.isIOS ? 'iOS' : deviceInfo.isAndroid ? 'Android' : 'Desktop'}</span>
          {lastISBN && <span className="isbn-detected">ISBN: {lastISBN}</span>}
        </div>
        
        {lastISBN && (
          <div className="isbn-result">
            <div className="isbn-info">
              <strong>ISBN Detectado:</strong> {lastISBN}
            </div>
            <div className="detection-count">
              Detecciones: {detectionHistory.length}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
