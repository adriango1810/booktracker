// Console visible para debugging móvil
export const setupMobileConsole = () => {
  const debugContent = document.getElementById('debug-content');
  if (!debugContent) return;

  const originalConsole = {
    log: console.log,
    error: console.error,
    warn: console.warn,
    info: console.info
  };

  const addLog = (type: string, ...args: any[]) => {
    const timestamp = new Date().toLocaleTimeString();
    const message = args.map(arg => 
      typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)
    ).join(' ');
    
    const logEntry = document.createElement('div');
    logEntry.style.cssText = `
      margin-bottom: 2px;
      padding: 2px 0;
      border-bottom: 1px solid #333;
      font-size: 11px;
    `;
    
    const colorMap = {
      log: '#0f0',
      error: '#f00',
      warn: '#ff0',
      info: '#0ff'
    };
    
    logEntry.innerHTML = `<span style="color: #888;">[${timestamp}]</span> <span style="color: ${colorMap[type as keyof typeof colorMap]}">${type.toUpperCase()}:</span> ${message}`;
    
    debugContent.appendChild(logEntry);
    
    // Mantener solo los últimos 20 logs
    while (debugContent.children.length > 20) {
      debugContent.removeChild(debugContent.firstChild);
    }
    
    // Auto-scroll al final
    debugContent.scrollTop = debugContent.scrollHeight;
  };

  // Sobrescribir console methods
  console.log = (...args) => {
    originalConsole.log(...args);
    addLog('log', ...args);
  };
  
  console.error = (...args) => {
    originalConsole.error(...args);
    addLog('error', ...args);
  };
  
  console.warn = (...args) => {
    originalConsole.warn(...args);
    addLog('warn', ...args);
  };
  
  console.info = (...args) => {
    originalConsole.info(...args);
    addLog('info', ...args);
  };
};
