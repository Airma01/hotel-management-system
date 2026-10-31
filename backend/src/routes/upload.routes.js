import express from 'express';
import { uploadSingleImage } from '../controllers/upload.controller.js';
import { uploadSingle } from '../middleware/upload.middleware.js';

const router = express.Router();

// POST /api/upload
router.post('/', uploadSingle, uploadSingleImage);

export default router;