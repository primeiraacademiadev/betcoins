import React from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './ui/App';
import { ToastProvider } from './ui/ToastProvider';
import './ui/styles.css';
createRoot(document.getElementById('root')!).render(<React.StrictMode><ToastProvider><App/></ToastProvider></React.StrictMode>);
