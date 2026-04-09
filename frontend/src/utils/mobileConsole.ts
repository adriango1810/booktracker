// Console visible para debugging móvil
export const setupMobileConsole = () => {
  let debugContent = document.getElementById('debug-content');
  
  // Si no existe, crearlo
  if (!debugContent) {
    const debugConsole = document.createElement('div');
    debugConsole.id = 'debug-console';
    debugConsole.style.cssText = `
      position: fixed;
      top: 10px;
      right: 10px;
      background: rgba(0,0,0,0.9);
      color: white;
      padding: 10px;
      font-size: 12px;
      max-width: 300px;
      max-height: 200px;
      overflow: auto;
      z-index: 9999;
      border-radius: 5px;
      font-family: monospace;
      border: 1px solid #444;
    `;
    
    const title = document.createElement('div');
    title.textContent = 'DEBUG LOGS:';
    title.style.cssText = 'font-weight: bold; margin-bottom: 5px; color: #0f0;';
    
    debugContent = document.createElement('div');
    debugContent.id = 'debug-content';
    debugContent.textContent = 'Iniciando...';
    
    debugConsole.appendChild(title);
    debugConsole.appendChild(debugContent);
    document.body.appendChild(debugConsole);
  }

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
    
    // Mantener solo los últimos 50 logs
    while (debugContent.children.length > 50) {
      const firstChild = debugContent.firstChild;
      if (firstChild) {
        debugContent.removeChild(firstChild);
      }
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
