import { useEffect, useState } from 'react';
import { CameraView } from './components/CameraView';
import './App.css';
import { setupMobileConsole } from './utils/mobileConsole';

function App() {
  const [cameraStarted, setCameraStarted] = useState(false);

  // Activar console visible para móvil
  useEffect(() => {
    setupMobileConsole();
    console.log('Mobile console activated');
  }, []);

  const handleFrameCapture = (imageData: ImageData) => {
    console.log('Frame captured for analysis:', imageData.width, 'x', imageData.height);
  };

  const startCamera = () => {
    setCameraStarted(true);
  };

  if (!cameraStarted) {
    return (
      <div className="app">
        <div className="start-screen">
          <div className="start-content">
            <h1>📷 Book Scanner</h1>
            <p>Escanea libros para encontrarlos en Goodreads</p>
            <button 
              onClick={startCamera}
              className="start-button"
            >
              Iniciar Cámara
            </button>
            <p className="start-note">
              Necesitas permitir el acceso a la cámara
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="app">
      <CameraView onFrameCapture={handleFrameCapture} />
    </div>
  );
}

export default App;
