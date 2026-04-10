import React, { useEffect, useRef, useCallback, useState } from 'react';
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

  // Función para enfocar al tocar la pantalla
  const handleVideoTap = useCallback((event: React.MouseEvent<HTMLVideoElement>) => {
    if (!videoRef.current) return;
    
    const video = videoRef.current;
    const rect = video.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    
    // Calcular coordenadas relativas al video (0-1)
    const relativeX = x / rect.width;
    const relativeY = y / rect.height;
    
    console.log('Tapping to focus at:', { relativeX, relativeY });
    
    // Intentar enfocar en el punto tocado (simplificado)
    const stream = video.srcObject as MediaStream;
    const track = stream?.getVideoTracks()[0];
    
    if (track) {
      // Mostrar indicador visual de toque
      const indicator = document.createElement('div');
      indicator.style.cssText = `
        position: fixed;
        left: ${event.clientX - 20}px;
        top: ${event.clientY - 20}px;
        width: 40px;
        height: 40px;
        border: 3px solid #00ff00;
        border-radius: 50%;
        pointer-events: none;
        z-index: 9999;
        animation: focusPulse 0.6s ease-out;
      `;
      document.body.appendChild(indicator);
      
      // Remover indicador después de la animación
      setTimeout(() => {
        document.body.removeChild(indicator);
      }, 600);
      
      // Intentar aplicar restricciones de enfoque (si el dispositivo lo soporta)
      try {
        // Intentar con pointsOfInterest (experimental)
        (track as any).applyConstraints({
          advanced: [{
            pointsOfInterest: [{ x: relativeX, y: relativeY }]
          }]
        }).catch(() => {
          console.log('Points of interest not supported, trying brightness adjustment');
          
          // Si no funciona, intentar ajustar brillo y contraste
          try {
            (track as any).applyConstraints({
              advanced: [{
                brightness: 0.1,  // Pequeño ajuste para forzar recalculación
                contrast: 1.1
              }]
            }).then(() => {
              // Volver a valores normales después de 500ms
              setTimeout(() => {
                (track as any).applyConstraints({
                  brightness: 0,
                  contrast: 1
                }).catch(() => console.log('Could not reset brightness'));
              }, 500);
            }).catch(() => {
              console.log('Brightness adjustment not supported');
            });
          } catch (error) {
            console.log('All focus methods failed, but tap indicator works');
          }
        });
      } catch (error) {
        console.log('Tap-to-focus API not available');
      }
    }
  }, []);

  useEffect(() => {
    // Activar escaneo ahora que la cámara funciona
    if (isReady && onFrameCapture) {
      console.log('Cámara lista - iniciando escaneo ISBN...');
      startScanning(handleFrameCapture!);
    } else {
      stopScanning();
    }
    
    return () => stopScanning();
  }, [isReady, onFrameCapture, startScanning, stopScanning, handleFrameCapture]);

  const [roi, setRoi] = useState({ x: 0, y: 0, width: 0, height: 0 });

  // Calcular ROI solo cuando el video esté listo
  useEffect(() => {
    if (isReady) {
      const newRoi = getROI();
      setRoi(newRoi);
    }
  }, [isReady, getROI]);

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
        onClick={handleVideoTap}
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
