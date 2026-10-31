import multer from 'multer';
import { AppError } from '../utils/AppError.js';

// Store file in memory (we upload the buffer to Cloudinary)
const storage = multer.memoryStorage();

const fileFilter = (req, file, cb) => {
  if (file.mimetype.startsWith('image/')) {
    cb(null, true);
  } else {
    cb(new AppError('Only image files are allowed!', 400), false);
  }
};

const upload = multer({
  storage,
  fileFilter,
  limits: {
    fileSize: 5 * 1024 * 1024, // 5MB limit
  },
});

// Single image upload
export const uploadSingle = upload.single('image');

// Multiple images (max 10)
export const uploadMultiple = upload.array('images', 10);