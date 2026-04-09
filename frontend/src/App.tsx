import { CameraView } from './components/CameraView';
import './App.css';

function App() {
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
