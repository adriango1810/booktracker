import { useState, useCallback, useRef, useEffect } from 'react';
import { BrowserMultiFormatReader } from '@zxing/browser';
import { DecodeHintType, BarcodeFormat } from '@zxing/library';

interface ISBNDetection {
  isbn: string;
  format: string;
  timestamp: number;
  confidence?: number;
}

interface UseISBNReaderProps {
  onISBNDetected?: (isbn: string) => void;
  debounceMs?: number;
}

export const useISBNReader = ({ 
  onISBNDetected, 
  debounceMs = 2000 
}: UseISBNReaderProps = {}) => {
  const [isReading, setIsReading] = useState(false);
  const [lastISBN, setLastISBN] = useState<string>('');
  const [detectionHistory, setDetectionHistory] = useState<ISBNDetection[]>([]);
  
  const readerRef = useRef<BrowserMultiFormatReader | null>(null);
  const lastDetectionTimeRef = useRef<number>(0);

  // Inicializar lector ZXing
  const initializeReader = useCallback(() => {
    if (!readerRef.current) {
      // Configurar hints para optimizar detección de ISBN (EAN-13)
      const hints = new Map();
      
      // Priorizar formatos EAN-13 (ISBN-13) y UPC-A/E (ISBN-10)
      hints.set(DecodeHintType.POSSIBLE_FORMATS, [
        BarcodeFormat.EAN_13,  // ISBN-13
        BarcodeFormat.UPC_A,   // ISBN-10 (a veces aparece como UPC-A)
        BarcodeFormat.UPC_E,   // ISBN-10 versión corta
      ]);
      
      // Activar TRY_HARDER para mejor detección en condiciones difíciles
      hints.set(DecodeHintType.TRY_HARDER, true);
      
      readerRef.current = new BrowserMultiFormatReader(hints);
      console.log('ZXing reader initialized with EAN-13 hints and TRY_HARDER');
    }
  }, []);

  // Validar formato ISBN
  const validateISBN = useCallback((rawISBN: string): string | null => {
    // Limpiar el ISBN de caracteres no numéricos excepto X
    const cleaned = rawISBN.replace(/[^0-9X]/gi, '');
    
    // ISBN-13 (13 dígitos, empieza con 978 o 979)
    if (cleaned.length === 13 && (cleaned.startsWith('978') || cleaned.startsWith('979'))) {
      // Validar dígito de control ISBN-13
      const digits = cleaned.split('').map(Number);
      const sum = digits.slice(0, 12).reduce((acc, digit, index) => {
        return acc + digit * (index % 2 === 0 ? 1 : 3);
      }, 0);
      const checkDigit = (10 - (sum % 10)) % 10;
      
      if (checkDigit === digits[12]) {
        return cleaned;
      }
    }
    
    // ISBN-10 (10 dígitos, último puede ser X)
    if (cleaned.length === 10) {
      const digits = cleaned.split('').map(char => char === 'X' ? 10 : parseInt(char));
      const sum = digits.slice(0, 9).reduce((acc, digit, index) => {
        return acc + digit * (10 - index);
      }, 0);
      const checkDigit = sum % 11;
      
      if (checkDigit === (cleaned[9] === 'X' ? 10 : parseInt(cleaned[9]))) {
        return cleaned;
      }
    }
    
    return null;
  }, []);

  // Preprocesar imagen para mejorar detección de ISBN
  const preprocessImageForZXing = useCallback((imageData: ImageData): HTMLCanvasElement => {
    // Configuración de escalado (mínimo 1024px en el lado largo)
    const MIN_LONG_EDGE = parseInt(import.meta.env.VITE_SCAN_DECODE_MIN_LONG_EDGE || '1024');
    
    const currentLongEdge = Math.max(imageData.width, imageData.height);
    const scaleFactor = Math.max(1, MIN_LONG_EDGE / currentLongEdge);
    
    const targetWidth = Math.round(imageData.width * scaleFactor);
    const targetHeight = Math.round(imageData.height * scaleFactor);
    
    // Canvas para el preprocesamiento
    const canvas = document.createElement('canvas');
    canvas.width = targetWidth;
    canvas.height = targetHeight;
    const ctx = canvas.getContext('2d');
    
    if (!ctx) {
      throw new Error('Could not get canvas context for preprocessing');
    }
    
    // Desactivar suavizado para mantener nitidez de las barras
    ctx.imageSmoothingEnabled = false;
    
    // Dibujar imagen escalada
    const tempCanvas = document.createElement('canvas');
    tempCanvas.width = imageData.width;
    tempCanvas.height = imageData.height;
    const tempCtx = tempCanvas.getContext('2d');
    
    if (!tempCtx) {
      throw new Error('Could not get temp canvas context');
    }
    
    tempCtx.putImageData(imageData, 0, 0);
    ctx.drawImage(tempCanvas, 0, 0, targetWidth, targetHeight);
    
    // Opcional: Mejorar contraste (desactivable con constante)
    const ENABLE_CONTRAST_BOOST = false; // Cambiar a true para activar
    if (ENABLE_CONTRAST_BOOST) {
      const imageData = ctx.getImageData(0, 0, targetWidth, targetHeight);
      const data = imageData.data;
      
      // Convertir a escala de grises y aumentar contraste
      for (let i = 0; i < data.length; i += 4) {
        const gray = data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114;
        const contrast = 1.5; // Factor de contraste
        const adjusted = ((gray - 128) * contrast) + 128;
        const clamped = Math.max(0, Math.min(255, adjusted));
        
        data[i] = clamped;     // R
        data[i + 1] = clamped; // G
        data[i + 2] = clamped; // B
        // Alpha (i + 3) se mantiene igual
      }
      
      ctx.putImageData(imageData, 0, 0);
    }
    
    // Log de preprocesamiento solo si escala es significativa (>1.5x)
    if (scaleFactor > 1.5) {
      console.log(`?? Image scaled: ${scaleFactor.toFixed(2)}x`);
    }
    
    return canvas;
  }, []);

  // Procesar frame para detectar ISBN
  const processFrame = useCallback(async (imageData: ImageData): Promise<void> => {
    if (!readerRef.current || isReading) {
      return;
    }

    const now = Date.now();
    
    // Debounce para evitar múltiples lecturas del mismo ISBN
    if (now - lastDetectionTimeRef.current < debounceMs) {
      return;
    }

    setIsReading(true);

    try {
      // Preprocesar imagen para mejorar detección
      const processedCanvas = preprocessImageForZXing(imageData);
      
      // Usar ZXing para detectar códigos de barras
      const result = await readerRef.current.decodeFromCanvas(processedCanvas);
      
      if (result && result.getText()) {
        const rawISBN = result.getText();
        
        // Validar que sea un ISBN válido
        const validISBN = validateISBN(rawISBN);
        
        if (validISBN && validISBN !== lastISBN) {
          console.log('?? ISBN detected:', validISBN);
          
          // Actualizar estado
          setLastISBN(validISBN);
          lastDetectionTimeRef.current = now;
          
          // Agregar al historial
          const detection: ISBNDetection = {
            isbn: validISBN,
            format: result.getBarcodeFormat().toString(),
            timestamp: now,
          };
          
          setDetectionHistory(prev => [...prev.slice(-9), detection]);
          
          // Notificar detección
          if (onISBNDetected) {
            onISBNDetected(validISBN);
          }
        } else if (!validISBN) {
          // Código detectado pero no es ISBN válido - silencioso para reducir ruido
        }
      }
    } catch (error) {
      // ZXing lanza errores cuando no encuentra códigos de barras - silencioso
    } finally {
      setIsReading(false);
    }
  }, [isReading, lastISBN, validateISBN, onISBNDetected, debounceMs]);

  // Resetear lector
  const reset = useCallback(() => {
    setLastISBN('');
    setDetectionHistory([]);
    lastDetectionTimeRef.current = 0;
    console.log('ISBN reader reset');
  }, []);

  // Limpiar recursos
  const cleanup = useCallback(() => {
    if (readerRef.current) {
      // BrowserMultiFormatReader no tiene método reset, simplemente lo eliminamos
      readerRef.current = null;
      console.log('ZXing reader cleaned up');
    }
  }, []);

  // Inicializar al montar
  useEffect(() => {
    initializeReader();
    return cleanup;
  }, [initializeReader, cleanup]);

  return {
    isReading,
    lastISBN,
    detectionHistory,
    processFrame,
    reset,
    cleanup,
  };
};
