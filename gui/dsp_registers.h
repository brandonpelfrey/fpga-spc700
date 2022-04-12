DSP_REGISTER(0, 0, VOLL0, "Left Channel Volume (Voice 0)")
DSP_REGISTER(1, 0, VOLR0, "Right Channel Volume (Voice 0)")
DSP_REGISTER(2, 0, PL0, "Pitch (Low 8 bits) (Voice 0)")
DSP_REGISTER(3, 0, PH0, "Pitch (High 4 bits) (Voice 0)")
DSP_REGISTER(4, 0, SRCN0, "Source Number (Voice 0)")
DSP_REGISTER(5, 0, ADSR10, "ADSR Config 1 (Voice 0)")
DSP_REGISTER(6, 0, ADSR20, "ADSR Config 2 (Voice 0)")
DSP_REGISTER(7, 0, GAIN0, "Envelope Gain (Voice 0)")
DSP_REGISTER(8, 0, ENVX0, "Current Envelope Value (Voice 0)")
DSP_REGISTER(9, 0, OUTX0, "Current waveform, after envelope, pre-volume (Voice 0)")
DSP_REGISTER(10, 0xFF, __invalid10, nullptr)
DSP_REGISTER(11, 0xFF, __invalid11, nullptr)
DSP_REGISTER(12, 0xFF, MVOLL, "Main Volume (left output)")
DSP_REGISTER(13, 0xFF, EFB, "Echo Feedback")
DSP_REGISTER(14, 0xFF, __invalid14, nullptr)
DSP_REGISTER(15, 0, COEF0, "FIR Filter Coefficient (Voice 0)")
DSP_REGISTER(16, 1, VOLL1, "Left Channel Volume (Voice 1)")
DSP_REGISTER(17, 1, VOLR1, "Right Channel Volume (Voice 1)")
DSP_REGISTER(18, 1, PL1, "Pitch (Low 8 bits) (Voice 1)")
DSP_REGISTER(19, 1, PH1, "Pitch (High 4 bits) (Voice 1)")
DSP_REGISTER(20, 1, SRCN1, "Source Number (Voice 1)")
DSP_REGISTER(21, 1, ADSR11, "ADSR Config 1 (Voice 1)")
DSP_REGISTER(22, 1, ADSR21, "ADSR Config 2 (Voice 1)")
DSP_REGISTER(23, 1, GAIN1, "Envelope Gain (Voice 1)")
DSP_REGISTER(24, 1, ENVX1, "Current Envelope Value (Voice 1)")
DSP_REGISTER(25, 1, OUTX1, "Current waveform, after envelope, pre-volume (Voice 1)")
DSP_REGISTER(26, 0xFF, __invalid26, nullptr)
DSP_REGISTER(27, 0xFF, __invalid27, nullptr)
DSP_REGISTER(28, 0xFF, MVOLR, "Main Volume (right output)")
DSP_REGISTER(29, 0xFF, __invalid29, nullptr)
DSP_REGISTER(30, 0xFF, __invalid30, nullptr)
DSP_REGISTER(31, 1, COEF1, "FIR Filter Coefficient (Voice 1)")
DSP_REGISTER(32, 2, VOLL2, "Left Channel Volume (Voice 2)")
DSP_REGISTER(33, 2, VOLR2, "Right Channel Volume (Voice 2)")
DSP_REGISTER(34, 2, PL2, "Pitch (Low 8 bits) (Voice 2)")
DSP_REGISTER(35, 2, PH2, "Pitch (High 4 bits) (Voice 2)")
DSP_REGISTER(36, 2, SRCN2, "Source Number (Voice 2)")
DSP_REGISTER(37, 2, ADSR12, "ADSR Config 1 (Voice 2)")
DSP_REGISTER(38, 2, ADSR22, "ADSR Config 2 (Voice 2)")
DSP_REGISTER(39, 2, GAIN2, "Envelope Gain (Voice 2)")
DSP_REGISTER(40, 2, ENVX2, "Current Envelope Value (Voice 2)")
DSP_REGISTER(41, 2, OUTX2, "Current waveform, after envelope, pre-volume (Voice 2)")
DSP_REGISTER(42, 0xFF, __invalid42, nullptr)
DSP_REGISTER(43, 0xFF, __invalid43, nullptr)
DSP_REGISTER(44, 0xFF, EVOLL, "Echo Volume (left output)")
DSP_REGISTER(45, 0xFF, PMON, "Pitch Modulation (1 bit per voice)")
DSP_REGISTER(46, 0xFF, __invalid46, nullptr)
DSP_REGISTER(47, 2, COEF2, "FIR Filter Coefficient (Voice 2)")
DSP_REGISTER(48, 3, VOLL3, "Left Channel Volume (Voice 3)")
DSP_REGISTER(49, 3, VOLR3, "Right Channel Volume (Voice 3)")
DSP_REGISTER(50, 3, PL3, "Pitch (Low 8 bits) (Voice 3)")
DSP_REGISTER(51, 3, PH3, "Pitch (High 4 bits) (Voice 3)")
DSP_REGISTER(52, 3, SRCN3, "Source Number (Voice 3)")
DSP_REGISTER(53, 3, ADSR13, "ADSR Config 1 (Voice 3)")
DSP_REGISTER(54, 3, ADSR23, "ADSR Config 2 (Voice 3)")
DSP_REGISTER(55, 3, GAIN3, "Envelope Gain (Voice 3)")
DSP_REGISTER(56, 3, ENVX3, "Current Envelope Value (Voice 3)")
DSP_REGISTER(57, 3, OUTX3, "Current waveform, after envelope, pre-volume (Voice 3)")
DSP_REGISTER(58, 0xFF, __invalid58, nullptr)
DSP_REGISTER(59, 0xFF, __invalid59, nullptr)
DSP_REGISTER(60, 0xFF, EVOLR, "Echo Volume (right output)")
DSP_REGISTER(61, 0xFF, NON, "Noise enable")
DSP_REGISTER(62, 0xFF, __invalid62, nullptr)
DSP_REGISTER(63, 3, COEF3, "FIR Filter Coefficient (Voice 3)")
DSP_REGISTER(64, 4, VOLL4, "Left Channel Volume (Voice 4)")
DSP_REGISTER(65, 4, VOLR4, "Right Channel Volume (Voice 4)")
DSP_REGISTER(66, 4, PL4, "Pitch (Low 8 bits) (Voice 4)")
DSP_REGISTER(67, 4, PH4, "Pitch (High 4 bits) (Voice 4)")
DSP_REGISTER(68, 4, SRCN4, "Source Number (Voice 4)")
DSP_REGISTER(69, 4, ADSR14, "ADSR Config 1 (Voice 4)")
DSP_REGISTER(70, 4, ADSR24, "ADSR Config 2 (Voice 4)")
DSP_REGISTER(71, 4, GAIN4, "Envelope Gain (Voice 4)")
DSP_REGISTER(72, 4, ENVX4, "Current Envelope Value (Voice 4)")
DSP_REGISTER(73, 4, OUTX4, "Current waveform, after envelope, pre-volume (Voice 4)")
DSP_REGISTER(74, 0xFF, __invalid74, nullptr)
DSP_REGISTER(75, 0xFF, __invalid75, nullptr)
DSP_REGISTER(76, 0xFF, KON, "Key On (1 bit per voice)")
DSP_REGISTER(77, 0xFF, EON, "Echo enable")
DSP_REGISTER(78, 0xFF, __invalid78, nullptr)
DSP_REGISTER(79, 4, COEF4, "FIR Filter Coefficient (Voice 4)")
DSP_REGISTER(80, 5, VOLL5, "Left Channel Volume (Voice 5)")
DSP_REGISTER(81, 5, VOLR5, "Right Channel Volume (Voice 5)")
DSP_REGISTER(82, 5, PL5, "Pitch (Low 8 bits) (Voice 5)")
DSP_REGISTER(83, 5, PH5, "Pitch (High 4 bits) (Voice 5)")
DSP_REGISTER(84, 5, SRCN5, "Source Number (Voice 5)")
DSP_REGISTER(85, 5, ADSR15, "ADSR Config 1 (Voice 5)")
DSP_REGISTER(86, 5, ADSR25, "ADSR Config 2 (Voice 5)")
DSP_REGISTER(87, 5, GAIN5, "Envelope Gain (Voice 5)")
DSP_REGISTER(88, 5, ENVX5, "Current Envelope Value (Voice 5)")
DSP_REGISTER(89, 5, OUTX5, "Current waveform, after envelope, pre-volume (Voice 5)")
DSP_REGISTER(90, 0xFF, __invalid90, nullptr)
DSP_REGISTER(91, 0xFF, __invalid91, nullptr)
DSP_REGISTER(92, 0xFF, KOF, "Key Off (1 bit per voice)")
DSP_REGISTER(93, 0xFF, DIR, "Source Directory Address (DIR * 0x100")
DSP_REGISTER(94, 0xFF, __invalid94, nullptr)
DSP_REGISTER(95, 5, COEF5, "FIR Filter Coefficient (Voice 5)")
DSP_REGISTER(96, 6, VOLL6, "Left Channel Volume (Voice 6)")
DSP_REGISTER(97, 6, VOLR6, "Right Channel Volume (Voice 6)")
DSP_REGISTER(98, 6, PL6, "Pitch (Low 8 bits) (Voice 6)")
DSP_REGISTER(99, 6, PH6, "Pitch (High 4 bits) (Voice 6)")
DSP_REGISTER(100, 6, SRCN6, "Source Number (Voice 6)")
DSP_REGISTER(101, 6, ADSR16, "ADSR Config 1 (Voice 6)")
DSP_REGISTER(102, 6, ADSR26, "ADSR Config 2 (Voice 6)")
DSP_REGISTER(103, 6, GAIN6, "Envelope Gain (Voice 6)")
DSP_REGISTER(104, 6, ENVX6, "Current Envelope Value (Voice 6)")
DSP_REGISTER(105, 6, OUTX6, "Current waveform, after envelope, pre-volume (Voice 6)")
DSP_REGISTER(106, 0xFF, __invalid106, nullptr)
DSP_REGISTER(107, 0xFF, __invalid107, nullptr)
DSP_REGISTER(108, 0xFF, FLG, "DSP Flags")
DSP_REGISTER(109, 0xFF, ESA, "Echo Buffer Address (ESA * 0x100)")
DSP_REGISTER(110, 0xFF, __invalid110, nullptr)
DSP_REGISTER(111, 6, COEF6, "FIR Filter Coefficient (Voice 6)")
DSP_REGISTER(112, 7, VOLL7, "Left Channel Volume (Voice 7)")
DSP_REGISTER(113, 7, VOLR7, "Right Channel Volume (Voice 7)")
DSP_REGISTER(114, 7, PL7, "Pitch (Low 8 bits) (Voice 7)")
DSP_REGISTER(115, 7, PH7, "Pitch (High 4 bits) (Voice 7)")
DSP_REGISTER(116, 7, SRCN7, "Source Number (Voice 7)")
DSP_REGISTER(117, 7, ADSR17, "ADSR Config 1 (Voice 7)")
DSP_REGISTER(118, 7, ADSR27, "ADSR Config 2 (Voice 7)")
DSP_REGISTER(119, 7, GAIN7, "Envelope Gain (Voice 7)")
DSP_REGISTER(120, 7, ENVX7, "Current Envelope Value (Voice 7)")
DSP_REGISTER(121, 7, OUTX7, "Current waveform, after envelope, pre-volume (Voice 7)")
DSP_REGISTER(122, 0xFF, __invalid122, nullptr)
DSP_REGISTER(123, 0xFF, __invalid123, nullptr)
DSP_REGISTER(124, 0xFF, ENDX, "End of Sample (1 bit per voice)")
DSP_REGISTER(125, 0xFF, EDL, "Echo Delay, 4 bits, higher values require more memory")
DSP_REGISTER(126, 0xFF, __invalid126, nullptr)
DSP_REGISTER(127, 7, COEF7, "FIR Filter Coefficient (Voice 7)")
