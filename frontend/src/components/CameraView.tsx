import React, { useEffect } from 'react';
import { useCamera } from '../hooks/useCamera';
import { useScanLoop } from '../hooks/useScanLoop';

interface CameraViewProps {
  onFrameCapture?: (imageData: ImageData) => void;
  className?: string;
}

export const CameraView: React.FC<CameraViewProps> = ({ 
  onFrameCapture, 
  className = '' 
}) => {
  const {
    isLoading,
    error,
    isReady,
    videoRef,
    deviceInfo,
    startCamera,
    stopCamera,
  } = useCamera();

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
    startCamera();
    return () => stopCamera();
  }, [startCamera, stopCamera]);

  useEffect(() => {
    console.log('CameraView useEffect:', { isReady, hasCallback: !!onFrameCapture });
    
    if (isReady && onFrameCapture) {
      console.log('Starting scanning...');
      startScanning(onFrameCapture);
    } else {
      console.log('Stopping scanning...');
      stopScanning();
    }
    
    return () => stopScanning();
  }, [isReady, onFrameCapture, startScanning, stopScanning]);

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

  if (isLoading) {
    return (
      <div className={`camera-loading ${className}`}>
        <div className="loading-spinner">
          <div className="spinner"></div>
          <p>Inicializando cámara...</p>
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
          <div className={`status-dot ${isScanning ? 'scanning' : 'idle'}`}></div>
          <span className="status-text">
            {isScanning ? 'Escaneando...' : 'Cámara lista'}
          </span>
        </div>
        
        <div className="scan-stats">
          <span>FPS: {fps}</span>
          <span>Frames: {frameCount}</span>
          <span>Dispositivo: {deviceInfo.isIOS ? 'iOS' : deviceInfo.isAndroid ? 'Android' : 'Desktop'}</span>
        </div>
      </div>
    </div>
  );
};
