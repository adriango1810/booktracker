import { useEffect } from 'react';
import { CameraView } from './components/CameraView';
import './App.css';
import { setupMobileConsole } from './utils/mobileConsole';

function App() {
  // Activar console visible para móvil
  useEffect(() => {
    setupMobileConsole();
    console.log('Mobile console activated');
  }, []);

  const handleFrameCapture = (imageData: ImageData) => {
    console.log('Frame captured for analysis:', imageData.width, 'x', imageData.height);
  };

  return (
    <div className="app">
      <CameraView onFrameCapture={handleFrameCapture} />
      
      {/* Console visible para debugging móvil */}
      <div 
        style={{
          position: 'fixed',
          top: '10px',
          right: '10px',
          background: 'rgba(0,0,0,0.8)',
          color: 'white',
          padding: '10px',
          fontSize: '12px',
          maxWidth: '300px',
          maxHeight: '200px',
          overflow: 'auto',
          zIndex: 9999,
          borderRadius: '5px',
          fontFamily: 'monospace'
        }}
        id="debug-console"
      >
        <div style={{fontWeight: 'bold', marginBottom: '5px'}}>DEBUG LOGS:</div>
        <div id="debug-content">Esperando logs...</div>
      </div>
    </div>
  );
}

export default App;
