import { useState, useCallback, useRef, useEffect } from 'react';
import { BrowserMultiFormatReader } from '@zxing/browser';

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
      readerRef.current = new BrowserMultiFormatReader();
      console.log('ZXing reader initialized');
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
      // Convertir ImageData a formato compatible con ZXing
      const canvas = document.createElement('canvas');
      canvas.width = imageData.width;
      canvas.height = imageData.height;
      const ctx = canvas.getContext('2d');
      
      if (!ctx) {
        throw new Error('Could not get canvas context');
      }

      ctx.putImageData(imageData, 0, 0);
      
      // Usar ZXing para detectar códigos de barras
      const result = await readerRef.current.decodeFromCanvas(canvas);
      
      if (result && result.getText()) {
        const rawISBN = result.getText();
        console.log('ISBN DETECTADO:', rawISBN);
        
        // Validar que sea un ISBN válido
        const validISBN = validateISBN(rawISBN);
        
        if (validISBN && validISBN !== lastISBN) {
          console.log('ISBN VÁLIDO:', validISBN);
          
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
          console.log('Código detectado pero no es ISBN válido:', rawISBN);
        }
      }
    } catch (error) {
      // ZXing lanza errores cuando no encuentra códigos de barras, es normal
      // No mostrar estos errores para reducir ruido
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
