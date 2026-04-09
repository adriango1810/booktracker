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
    </div>
  );
}

export default App;
