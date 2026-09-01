# eden-for-mali (ภาษาไทย)

การปรับแต่งการ build ของ [Eden](https://git.eden-emu.dev/eden-emu/eden)
(โปรแกรมจำลอง Nintendo Switch) ให้เหมาะกับ **GPU Arm Mali / Immortalis**
โดยเจาะจงที่ **Samsung Galaxy Tab S11 / S11 Ultra** (MediaTek Dimensity 9400+,
Cortex-X925, Arm Immortalis-G925 MC12)

repo นี้ **ไม่ได้ fork** Eden ทั้งก้อน แต่เก็บเป็น patch ชุดเล็กที่ตรวจทานได้
พร้อมสคริปต์และ CI ที่ build ไฟล์ APK จาก Eden เวอร์ชันที่ pin ไว้

## สรุปผลการตรวจสอบ

**Eden รองรับ Mali อยู่แล้วในระดับที่ดีมาก** และส่วนใหญ่ตัดสินใจจาก
"ความสามารถที่ไดรเวอร์รายงาน" ไม่ใช่การ hardcode ตามยี่ห้อ GPU
นี่คือข้อค้นพบหลัก และเป็นเหตุผลที่ patch ใน repo นี้มีแค่ 2 ตัว

Vulkan backend ของ Eden มีการจัดการ `VK_DRIVER_ID_ARM_PROPRIETARY` เป็นกรณีพิเศษ
อยู่แล้ว 6 จุด, มองว่า Mali เป็น tile-based renderer ทั่วทั้งโค้ด และการตั้งค่า
shader compiler ทุกตัวมาจากการ query ความสามารถของอุปกรณ์จริง
รายละเอียดพร้อมเลขบรรทัดอยู่ใน [`FINDINGS.md`](FINDINGS.md)

ดังนั้นผมจึงเก็บเฉพาะจุดที่ได้ผลจริงและตรวจสอบได้ คือ **เป้าหมายของคอมไพเลอร์**
(patch 0001), **ระบบ log** (patch 0002) และ **การตั้งค่าในแอป**
([`TAB-S11-TUNING.md`](TAB-S11-TUNING.md))

ผมไม่ใส่ "การแก้บั๊กไดรเวอร์" ที่เดาเอาเอง เพราะการคัดลอกวิธีแก้ของ Adreno
มาใส่ Mali โดยไม่ได้วัดผลบนเครื่องจริง มีแต่จะทำให้ช้าลง ไม่ใช่เร็วขึ้น

## patch ทั้งสองตัวทำอะไร

| Patch | ผล |
| --- | --- |
| `0001-cmake-add-armv9-x925-arm64-build-preset` | เพิ่ม `YUZU_BUILD_PRESET=armv9-x925` ซึ่ง build ด้วยฐาน ISA `armv9-a` และจัดลำดับคำสั่งให้เหมาะกับคอร์ Cortex-X925 ของ Dimensity 9400+ **นี่คือตัวเดียวที่มีผลด้านความเร็วจริง** และการจำลอง Switch นั้นใช้ CPU หนักกว่า GPU ในหลายกรณี |
| `0002-video_core-identify-the-Arm-proprietary-driver-in-GP` | ระบบ GPU log ของ Eden รู้จัก Turnip กับ Qualcomm แต่รายงาน Mali/Immortalis เป็น "Unknown" — patch นี้เพิ่มชนิดไดรเวอร์ `Mali` เพื่อให้ log ใช้ปรับแต่งได้จริง และบันทึกเหตุผลในโค้ดว่าทำไม Arm จึงไม่อยู่ใน `Device::ShouldBoostClocks()` |

> **APK แบบ `armv9-x925` ต้องใช้เครื่องที่เป็น Armv9 เท่านั้น**
> ถ้าเอาไปลงเครื่องรุ่นเก่ากว่านั้นจะเปิดไม่ขึ้น — ให้ใช้ preset
> `optimized` หรือ `generic` แทน

## ข้อค้นพบสำคัญ: "Force maximum clocks" ไม่ทำงานบน Mali

บน Android ฟีเจอร์นี้ทำผ่าน `adrenotools_set_turbo()` เท่านั้น ซึ่งเป็นของ
Qualcomm โดยเฉพาะ (ส่วนที่ใช้ compute shader ถูก `#ifndef __ANDROID__` ตัดออก)
บน Mali มันจึงเพิ่มความเร็วสัญญาณนาฬิกาไม่ได้เลย

**ให้ปิดตัวเลือกนี้ไว้** เพราะถ้าเปิด (หรือถ้ามีใครไป "แก้" ให้ Arm เข้าลิสต์)
จะได้แค่เธรดที่กินไฟเปล่า ๆ และบนแท็บเล็ตที่จำกัดด้วยความร้อน
ไฟที่เสียไปคือเฟรมเรตที่หายไป

## วิธีเอาไฟล์ APK

**จาก CI (แนะนำ)** — ไปที่แท็บ Actions → *Build Eden APK (Mali / Galaxy Tab S11)*
→ *Run workflow* เลือก preset กับ build type แล้วรอ ไฟล์ APK และ AAB
จะขึ้นเป็น artifact ให้ดาวน์โหลด

APK จะถูก sign ด้วย debug key ที่มาพร้อม Eden จึงติดตั้งได้เลย และอยู่แยกกับ
Eden ตัวจริงที่ลงไว้ (ไม่ทับกัน)

**build เองบนเครื่อง**

```sh
./scripts/prepare-source.sh          # clone Eden ตาม commit ที่ pin + ใส่ patch
./scripts/build-apk.sh               # ต้องมี JDK 17 + Android SDK/NDK
# ไฟล์ APK จะอยู่ใน eden-src/artifacts/
```

รายละเอียดสิ่งที่ต้องมีอยู่ใน [`BUILD.md`](BUILD.md)

## การตั้งค่าที่แนะนำสำหรับ Tab S11

ดูตารางเต็มใน [`TAB-S11-TUNING.md`](TAB-S11-TUNING.md) สรุปสั้น ๆ:

- **ปิด** Force maximum clocks (เหตุผลด้านบน)
- **ASTC recompression: Uncompressed** — Immortalis-G925 รองรับ ASTC ในฮาร์ดแวร์
  อยู่แล้ว จึงไม่ต้องถอดรหัสเลย การไป recompress คือทิ้งข้อดีนี้
- **VRAM usage mode: Aggressive** — ค่าเริ่มต้น `Conservative` ตั้งมาเพื่อมือถือ
  RAM 6–8 GB ส่วน Tab S11 มี 12–16 GB
- **Resolution scale: 1x** ก่อน ให้นิ่งแล้วค่อยลอง 1.5x
- **Asynchronous shaders: เปิด** ลดอาการกระตุกตอนคอมไพล์ shader
- **อย่าเล่นตอนเสียบชาร์จ** ความร้อนจากการชาร์จทำให้ SoC ลดความเร็ว
  ซึ่งกระทบเฟรมเรตมากกว่าการปรับตัวเลือกใด ๆ ข้างต้น

## สิ่งที่ยังไม่ได้ทำ

**ยังไม่มีการวัดผลบนเครื่อง Galaxy Tab S11 จริง** เพราะสภาพแวดล้อมที่ build
ไม่มีอุปกรณ์ Android ใด ๆ ให้ทดสอบ ผมจึงตั้งใจให้ patch ปลอดภัยที่สุด:
0001 แก้แค่ flag ของคอมไพเลอร์ และ 0002 แก้แค่ข้อความ log กับคอมเมนต์ —
ไม่มีตัวไหนเปลี่ยนพฤติกรรมการเรนเดอร์

ให้ถือว่าคู่มือการตั้งค่าเป็น "จุดเริ่มต้นให้ไปวัดผลต่อ" ไม่ใช่ตัวเลขที่พิสูจน์แล้ว

## ลิขสิทธิ์

Eden ใช้ GPL-3.0-or-later — patch ในนี้ถือเป็นงานต่อเนื่องจึงใช้สัญญาเดียวกัน
Eden เป็นโปรแกรมจำลอง ไม่มีโค้ด/คีย์/เฟิร์มแวร์/เกมของ Nintendo มาให้
และ repo นี้ก็เช่นกัน ผู้ใช้ต้องเตรียมส่วนนั้นจากเครื่องที่ตัวเองเป็นเจ้าของ
