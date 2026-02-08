# MoonBit メモリ管理ライブラリ設計文書

## 1. 動機と目標

本ライブラリは、DSP・パーサー・CRDT・インクリメンタル計算という4つのドメインに
共通するメモリ管理パターンを統一的に扱うことを目的とする。

### 1.1 解決すべき問題

```
┌─────────────────────────────────────────────────────────┐
│  MoonBit GC (Perceus / RC)                              │
│                                                         │
│  ✓ 通常のアプリケーションコードには十分                  │
│  ✗ リアルタイムDSPでGC pauseが許容できない              │
│  ✗ パーサーの大量一時ASTノードでRC操作がオーバーヘッド   │
│  ✗ フェーズ単位の一括解放パターンを表現できない          │
│  ✗ use-after-free/use-after-resetを型レベルで防げない    │
└─────────────────────────────────────────────────────────┘
```

### 1.2 設計原則

1. **段階的採用** — GCで十分な箇所はGCのまま。必要な箇所だけArenaを使う
2. **責務分離** — 物理メモリ管理(C)と論理ライフタイム管理(MoonBit)を分ける
3. **バックエンド選択可能** — native専用(C-FFI)と全バックエンド対応(Pure MoonBit)を切り替え可能
4. **ドメイン非依存** — DSPもパーサーも同じプリミティブの上に構築する

---

## 2. アーキテクチャ全体像

```
┌─────────────────────────────────────────────────────────────────┐
│                    ユーザードメイン層                            │
│                                                                 │
│  AudioBufferPool    ASTArena      CRDTOpPool    MemoTable       │
│  (DSP用)            (パーサー用)  (CRDT用)      (incr用)        │
│                                                                 │
├──────────────────────── ↓ 利用 ↓ ───────────────────────────────┤
│                                                                 │
│                    型付きArena層 (Layer 3)                       │
│                                                                 │
│  TypedArena[T]  — ドメイン型Tに特化したArena                    │
│  TypedRef[T]    — 型情報+generational indexで型安全な参照        │
│                                                                 │
├──────────────────────── ↓ 利用 ↓ ───────────────────────────────┤
│                                                                 │
│                    汎用Arena層 (Layer 2)                         │
│                                                                 │
│  Arena           — スロットベースのアロケータ                    │
│  Ref             — generational index (offset + generation)     │
│  GenStore (trait) — generation配列の抽象ストレージ               │
│                                                                 │
├──────────────────────── ↓ 利用 ↓ ───────────────────────────────┤
│                                                                 │
│                    物理メモリ層 (Layer 1)                        │
│                                                                 │
│  BumpAllocator (trait) — 物理バイト列の割り当て/リセット        │
│  ├─ CFFIBump          — C malloc/mmap経由 (GCフリー)            │
│  └─ MbBump            — FixedArray[Byte]経由 (全バックエンド)   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Layer 1: 物理メモリ層

### 3.1 役割

OSまたはMoonBitランタイムからraw bytesを確保し、bump pointer方式で
高速に割り当てる。型の概念を持たない。バイト列とオフセットのみ。

### 3.2 型定義

```
BumpAllocator (trait)
│
│  意味: 連続したバイト列を管理し、先頭から順に切り出す。
│        個別解放はしない。reset()で全領域を一括再利用する。
│
│  操作:
│    alloc(size: Int, align: Int) -> Int?
│      割り当てに成功したらオフセットを返す。
│      失敗(容量不足)ならNone。
│
│    reset() -> Unit
│      オフセットを0に戻す。メモリは解放しない。
│      以前のオフセットは全て無効になる。
│
│    capacity() -> Int
│      総容量(バイト)
│
│    used() -> Int
│      使用済みバイト数
│
│  不変条件:
│    - alloc()は常にoffsetを前進させる（後退しない）
│    - reset()後、used() == 0
│    - alloc()が返すオフセットはalignの倍数
│    - alloc()成功後、そのスロット範囲のwrite/readはresetまで成功する
```

### 3.3 実装A: CFFIBump (native専用)

```
CFFIBump
│
│  内部: C側でmalloc確保したバイト列へのopaqueポインタ
│  メモリ所有権: C側。MoonBitのfinalizerでfree。
│  GC関与: なし（DSPホットパス向き）
│
│  C関数:
│    bump_create(capacity: Int) -> Ptr
│    bump_alloc(ptr: Ptr, size: Int, align: Int) -> Int
│    bump_reset(ptr: Ptr) -> Unit
│    bump_destroy(ptr: Ptr) -> Unit
│    bump_write_bytes(ptr: Ptr, offset: Int, data: Ptr, len: Int) -> Unit
│    bump_read_bytes(ptr: Ptr, offset: Int, out: Ptr, len: Int) -> Unit
│    bump_write_f64(ptr: Ptr, offset: Int, val: Double) -> Unit
│    bump_read_f64(ptr: Ptr, offset: Int) -> Double
│    bump_write_i32(ptr: Ptr, offset: Int, val: Int) -> Unit
│    bump_read_i32(ptr: Ptr, offset: Int) -> Int
```

### 3.4 実装B: MbBump (全バックエンド)

```
MbBump
│
│  内部: FixedArray[Byte] + mut offset: Int
│  メモリ所有権: MoonBit GC管理下
│  GC関与: あり（配列自体はGCが追跡する）
│
│  用途: wasm-gc/JSバックエンド、またはGC pauseが許容される場面
│
│  注意: FixedArray[Byte]へのread/writeは
│        MoonBitのBytesView等を使うか、
│        手動でバイト⇔型変換を実装する必要がある
```

### 3.5 Layer 1の意味論まとめ

```
状態遷移:

  Created ──alloc()──→ Allocated ──alloc()──→ Allocated ── ... ──→ Full
     │                     │                     │
     └────── reset() ──────┘──── reset() ────────┘
                 │
                 ▼
             Created (論理的に初期状態と同じ)

全てのオフセットは reset() により無効化される。
しかし Layer 1 自体はその無効化を検出しない。
無効アクセスの検出は Layer 2 の責務。
```

---

## 4. Layer 2: 汎用Arena層

### 4.1 役割

Layer 1の物理バイト列の上に「スロット」の概念を導入し、
generational indexによるuse-after-reset検出を提供する。
まだ型情報は持たない。

### 4.2 型定義

```
Ref
│
│  意味: Arena内の特定スロットへの参照。
│        スロットの物理位置(offset)と、
│        割り当て時の世代(generation)のペア。
│
│  フィールド:
│    index: Int        — スロット番号（0-origin）
│    generation: Int   — 割り当て時のArena世代
│
│  性質:
│    - Copy型（軽量、参照カウント不要）
│    - 比較可能（同一スロット・同一世代なら同一）
│    - 世代が一致しないとき、このRefは「stale」（無効）
│
│  ライフタイム意味論:
│    valid(ref, arena) ⟺ ref.generation == arena.slot_generation(ref.index)
│
│    Arena.reset() 後:
│      ∀ref. valid(ref, arena) == false
│      （全Refが一斉に無効化される）
```

```
GenStore (trait)
│
│  意味: スロットごとの世代番号を格納するストレージ。
│        Layer 1のBumpAllocatorと同様に、
│        実装をMoonBit/Cで切り替え可能にするための抽象。
│
│  操作:
│    get(index: Int) -> Int          — スロットの現在世代を取得
│    set(index: Int, gen: Int)       — スロットの世代を設定
│    length() -> Int                 — スロット総数
│    invalidate_all(new_gen: Int)    — 全スロットをnew_genに更新
│                                      （reset時に呼ぶ）
│
│  実装:
│    MbGenStore  — Array[Int]、GC管理下、全バックエンド
│    CGenStore   — C側 int配列、GCフリー、native専用
```

```
Arena
│
│  意味: 固定サイズスロットのプール。
│        物理メモリ(BumpAllocator)と世代管理(GenStore)を組み合わせ、
│        alloc/get/resetの安全なインターフェースを提供する。
│
│  フィールド:
│    bump: BumpImpl           — 物理メモリバックエンド
│    gen_store: GenStoreImpl  — 世代ストレージバックエンド
│    mut generation: Int      — 現在のArena全体の世代
│    mut count: Int           — 割り当て済みスロット数
│    slot_size: Int           — 1スロットのバイト数
│    max_slots: Int           — 最大スロット数
│
│  操作:
│    alloc() -> Ref?
│      新しいスロットを割り当て、Refを返す。
│      容量不足ならNone。
│      事後条件: gen_store.get(ref.index) == self.generation
│
│    is_valid(ref: Ref) -> Bool
│      ref.generation == gen_store.get(ref.index)
│
│    reset() -> Unit
│      bump.reset()
│      generation += 1
│      count = 0
│      注意: gen_store.invalidate_all()は遅延可能
│            （allocate時に上書きするため、即時全書き換え不要）
│
│    slot_offset(ref: Ref) -> Int?
│      is_valid(ref)ならrefに対応する物理オフセットを返す。
│      無効ならNone。
│
│  不変条件:
│    - count <= max_slots
│    - 割り当て済みスロット i (0 <= i < count) について:
│      gen_store.get(i) == generation
│    - generation は単調増加
```

### 4.3 resetの遅延無効化の意味論

```
素朴な実装:
  reset() {
    bump.reset()
    generation += 1
    count = 0
    for i in 0..max_slots { gen_store.set(i, -1) }  // O(n)
  }

遅延無効化:
  reset() {
    bump.reset()
    generation += 1  // これだけで全Refが論理的に無効
    count = 0
    // gen_storeは書き換えない！
  }

  is_valid(ref) {
    // 古い世代のエントリが残っていても、
    // ref.generationとarena.generationの両方を見れば判定できる
    ref.generation == self.generation &&
    ref.index < self.count &&
    gen_store.get(ref.index) == ref.generation
  }

  alloc() {
    // 新しいスロットにのみ現在の世代を書く
    gen_store.set(count, self.generation)
    ...
  }

結果: reset()がO(1)になる。DSPのブロック境界で毎回呼んでもコスト最小。
```

### 4.4 Arena世代のオーバーフロー

```
generationはIntだが、2^31回resetしても問題ないか？

仮にオーディオコールバックが44100Hz/256samples = 172回/秒とすると:
  2^31 / 172 / 3600 / 24 / 365 ≈ 395年

実用上オーバーフローは問題にならない。
念のためオーバーフロー時にgen_storeを全クリアする防御的実装は可能。
```

---

## 5. Layer 3: 型付きArena層

### 5.1 役割

Layer 2のバイト列スロットに型情報を付与し、
ドメイン型Tの値をシリアライズ/デシリアライズして読み書きする。

### 5.2 型定義

```
TypedRef[T]
│
│  意味: Arena内の型T値への参照。
│        Refをラップし、型パラメータTで
│        異なるArena間の参照混同をコンパイル時に防ぐ。
│
│  フィールド:
│    ref: Ref  — 内部の生参照
│
│  性質:
│    - TypedRef[AudioBuffer]をASTArenaに渡すとコンパイルエラー
│    - ゼロコスト抽象化（内部はRefそのもの）
```

```
Storable (trait)
│
│  意味: Arena上にバイト列として格納可能な型。
│        固定サイズのシリアライゼーションを定義する。
│
│  操作:
│    byte_size() -> Int
│      この型の1インスタンスに必要なバイト数。
│      全インスタンスで同じ値を返す（固定サイズ）。
│
│    write_to(self: Self, bump: BumpImpl, offset: Int) -> Unit
│      selfをbumpのoffset位置にバイト列として書き込む。
│
│    read_from(bump: BumpImpl, offset: Int) -> Self
│      bumpのoffset位置からバイト列を読み、Self値を構築する。
│
│  実装例:
│    Double — 8バイト、bump_write_f64/bump_read_f64
│    Int    — 4バイト、bump_write_i32/bump_read_i32
│    AudioFrame { left: Double, right: Double } — 16バイト
│    (ユーザー定義の固定サイズ構造体)
│
│  制約:
│    - 可変長データ(String, Array)は直接Storableにできない
│    - 可変長データはArena内オフセットへの間接参照で表現する
│      (後述のLayer 3拡張を参照)
```

```
TypedArena[T: Storable]
│
│  意味: 型Tに特化したArena。
│        Layer 2のArenaをラップし、型安全なAPIを提供する。
│
│  フィールド:
│    arena: Arena  — 内部の汎用Arena
│
│  操作:
│    alloc(value: T) -> TypedRef[T]?
│      スロットを確保し、valueを書き込み、型付き参照を返す。
│      alloc成功後の初期化write失敗は
│      BumpAllocator契約違反としてabortする。
│
│    get(ref: TypedRef[T]) -> T?
│      参照が有効なら値を読み出す。staleならNone。
│
│    set(ref: TypedRef[T], value: T) -> Bool
│      参照が有効なら値を上書き。staleならfalse。
│
│    reset() -> Unit
│      内部Arena.reset()を呼ぶ。全TypedRefが無効化。
│
│  注意 (MoonBitのtrait制約):
│    MoonBitではstruct TypedArena[T: Storable]と書けない可能性がある。
│    その場合、TypedArenaはコード生成マクロ or 手動特殊化で実装する。
│    あるいは、TypedArenaを使わずArena + Storable関数を
│    直接組み合わせるユーティリティ関数群として提供する。
```

### 5.3 MoonBitのtrait制約への対処パターン

```
MoonBitでは trait に型パラメータがないため、
TypedArena[T] を直接ジェネリックに書くのが難しい場合がある。

パターンA: 具体型ごとに特殊化

  struct F64Arena { arena: Arena }
  struct AudioFrameArena { arena: Arena }

  fn F64Arena::alloc(self, val: Double) -> TypedRef[Double]? { ... }
  fn AudioFrameArena::alloc(self, val: AudioFrame) -> TypedRef[AudioFrame]? { ... }

  利点: シンプル、最適化しやすい
  欠点: ボイラープレート

パターンB: クロージャベースの抽象化

  struct TypedArena {
    arena: Arena
    write_fn: (BumpImpl, Int, ???) -> Unit  // 型消去が必要
    read_fn:  (BumpImpl, Int) -> ???
  }

  利点: 1つの型で済む
  欠点: 型安全性が失われる、クロージャのオーバーヘッド

パターンC: コード生成 (推奨)

  マクロまたはビルドスクリプトで
  具体型ごとのArenaコードを自動生成する。
  パターンAの利点を保ちつつボイラープレートを排除。

現実的な推奨:
  まずパターンAで2〜3のドメイン型(Double, AudioFrame, ASTNode)を
  手動で実装し、共通パターンを抽出してからコード生成を検討する。
```

---

## 6. ドメイン特化層: 利用パターン

### 6.1 DSP: AudioBufferPool

```
AudioBufferPool
│
│  目的: オーディオコールバック内でGCなしにバッファを確保/再利用
│
│  構造:
│    frames_per_buffer: Int        — 1バッファのフレーム数 (例: 256)
│    channels: Int                 — チャンネル数 (例: 2)
│    arena: Arena                  — 1スロット = frames * channels * 8 bytes
│
│  ライフサイクル:
│    1. audio_callback開始時: arena.reset()
│    2. 一時バッファ確保: arena.alloc()
│    3. DSP処理: bump_read_f64 / bump_write_f64 で直接読み書き
│    4. audio_callback終了: 何もしない（次のreset()まで有効）
│
│  重要な性質:
│    - コールバック内でのallocは O(1)
│    - コールバック内でのGC発生は 0回
│    - reset()は O(1)（遅延無効化）
│    - バッファ間コピーは memcpy (C-FFI) で実装可能
│
│  注意:
│    コールバックをまたいでRefを保持してはならない。
│    reset()で無効化されるため、is_valid()がfalseを返す。
│    永続的なバッファ（ディレイライン等）は別のArenaまたは
│    通常のMoonBit配列で管理する。
```

### 6.2 パーサー: ASTArena

```
ASTArena
│
│  目的: パースフェーズで大量のASTノードを高速に割り当て、
│        フェーズ終了後に一括解放する。
│
│  構造:
│    node_arena: Arena       — ASTノード本体
│    string_arena: Arena     — 識別子等の文字列データ（可変長）
│
│  ASTノードの表現:
│    ASTノードはArena内では固定サイズのレコードとして格納。
│    子ノードへの参照はRefで表現。
│
│    例: BinaryExpr = { op: Int, left: Ref, right: Ref }
│                      4 bytes   8 bytes   8 bytes = 20 bytes/slot
│
│  可変長データ（文字列）の扱い:
│    文字列はstring_arenaに直接書き込み、
│    ASTノード内にはstring_arenaへのオフセット+長さを持たせる。
│
│    StringRef = { offset: Int, length: Int }  — 8 bytes
│
│  フェーズ遷移:
│    parse() {
│      ast_arena = Arena::new(...)
│      string_arena = Arena::new(...)
│      ... パース処理 ...
│      result = convert_to_persistent(ast_arena)  // GC管理下にコピー
│      ast_arena.reset()      // 一括解放
│      string_arena.reset()
│      return result
│    }
│
│  インクリメンタルパーサーとの統合:
│    incrライブラリのMemoノードがASTArenaのRefを保持する場合、
│    Arena.reset()のタイミングとMemoの無効化を同期させる必要がある。
│    → incr.generation と Arena.generation を連動させることで解決可能。
```

### 6.3 CRDT: CRDTOpPool

```
CRDTOpPool
│
│  目的: CRDT操作の一時的なバッチ処理を効率化する。
│
│  構造:
│    op_arena: Arena  — 操作データの一時格納
│
│  パターン:
│    リモートからの操作バッチを受信
│    → op_arenaに一時展開
│    → FugueTreeに適用
│    → op_arena.reset()
│
│  性質:
│    CRDTの永続データ（FugueTree）自体はGC管理下に置く。
│    Arenaは操作の「処理中」状態のみに使う。
│    これはMbBump（全バックエンド版）で十分な可能性が高い。
```

### 6.4 incr: MemoTable

```
MemoTable
│
│  目的: インクリメンタル計算のメモ化テーブルで、
│        世代ごとにキャッシュを管理する。
│
│  構造:
│    通常のMoonBit HashMap + generation counter
│    （Arenaではなく、generational indexの概念だけを借用）
│
│  パターン:
│    世代N: Signal変更 → 依存するMemoを無効化 → 再計算
│    世代N+1: 新しいSignal変更 → ...
│
│    各Memoエントリに generation を持たせ、
│    現在の世代と一致しないエントリを stale とみなす。
│
│  Arenaとの関係:
│    MemoTable自体はArenaを使わなくてもよい。
│    しかし、Memoの計算結果が大きな一時データ構造を含む場合、
│    その一時データをArenaに格納する選択肢がある。
│    これにより、世代遷移時の一括解放がO(1)になる。
```

---

## 7. バックエンド切り替えの設計

### 7.1 パッケージ構成

```
arena/
├── core/                    # バックエンド非依存の共通定義
│   ├── ref.mbt             # Ref, TypedRef 型定義
│   ├── arena.mbt           # Arena構造体、主要ロジック
│   └── storable.mbt        # Storable trait定義
│
├── bump/
│   ├── trait.mbt           # BumpAllocator trait定義
│   ├── mb_bump.mbt         # MbBump (FixedArray実装、全バックエンド)
│   └── c_bump.mbt          # CFFIBump (C-FFI実装、native専用)
│   └── c_bump.c            # C側のbump allocator実装
│
├── gen_store/
│   ├── trait.mbt           # GenStore trait定義
│   ├── mb_gen.mbt          # MbGenStore (Array[Int]実装)
│   └── c_gen.mbt           # CGenStore (C-FFI実装)
│   └── c_gen.c             # C側のgeneration配列実装
│
├── config/                  # バックエンド選択
│   ├── debug.mbt           # MbBump + MbGenStore を使う構成
│   └── release.mbt         # CFFIBump + CGenStore を使う構成
│
└── domain/                  # ドメイン特化のユーティリティ
    ├── audio_buffer.mbt    # AudioBufferPool
    ├── ast_arena.mbt       # ASTArena
    └── ...
```

### 7.2 切り替え方式: enum dispatch

```
enum BumpImpl {
  Mb(MbBump)
  C(CFFIBump)
}

enum GenStoreImpl {
  Mb(MbGenStore)
  C(CGenStore)
}

struct Arena {
  bump: BumpImpl
  gen_store: GenStoreImpl
  ...
}
```

```
構成選択:

  fn Arena::new_debug(slot_count: Int, slot_size: Int) -> Arena
    → BumpImpl::Mb + GenStoreImpl::Mb

  fn Arena::new_release(slot_count: Int, slot_size: Int) -> Arena
    → BumpImpl::C + GenStoreImpl::C

  fn Arena::new_hybrid(slot_count: Int, slot_size: Int) -> Arena
    → BumpImpl::C + GenStoreImpl::Mb
    （物理メモリはGCフリー、世代チェックはMoonBit側）
```

### 7.3 enum dispatchのコスト分析

```
matchのコスト: 分岐予測が効けば ~1ns

比較対象:
  - C-FFI呼び出し: ~5-20ns (関数ポインタ間接呼び出し)
  - bump_alloc自体: ~2-5ns (ポインタ加算のみ)
  - f64のread/write: ~1ns

結論:
  enum matchのコストはC-FFI呼び出しと比べて無視できる。
  DSPの毎サンプル処理で問題になるのはenum matchではなく、
  C-FFI呼び出しの回数。

  最適化戦略:
    毎サンプルでarena.get_sample()を呼ぶのではなく、
    バッファポインタ(オフセット)を取得して
    フレームループ内ではC側で直接読み書きする。

    fn process_block(arena: Arena, ref: Ref, frames: Int) {
      // refの有効性チェックは1回だけ
      let offset = arena.slot_offset(ref).unwrap()
      // フレームループはC側に委譲
      c_process_block(arena.bump_ptr(), offset, frames)
    }
```

---

## 8. 安全性の階層

```
                         安全性レベル
                              │
  ┌───────────────────────────┼───────────────────────────┐
  │                           │                           │
  │  Level 3: 型安全          │  TypedRef[T]による       │
  │  (コンパイル時)           │  型の混同防止             │
  │                           │                           │
  ├───────────────────────────┼───────────────────────────┤
  │                           │                           │
  │  Level 2: 世代安全        │  generational indexによる │
  │  (実行時チェック)         │  use-after-reset検出      │
  │                           │                           │
  ├───────────────────────────┼───────────────────────────┤
  │                           │                           │
  │  Level 1: 境界安全        │  offset < capacityの      │
  │  (実行時チェック)         │  境界チェック             │
  │                           │                           │
  ├───────────────────────────┼───────────────────────────┤
  │                           │                           │
  │  Level 0: unsafe          │  チェックなし             │
  │  (DSPホットパス用)        │  C側で直接read/write      │
  │                           │                           │
  └───────────────────────────┴───────────────────────────┘

原則:
  - 開発中は Level 2〜3 を使い、バグを早期発見する
  - プロファイリング後、ホットパスのみ Level 0 に降格
  - Level 0 の使用箇所は明示的にマークし、最小限に保つ

実装:
  fn get_checked(arena: Arena, ref: Ref) -> Bytes?    // Level 2
  fn get_unchecked(arena: Arena, ref: Ref) -> Bytes   // Level 0
```

---

## 9. 成長戦略: GrowableArena

```
基本Arenaは固定サイズ。パーサー等では事前にサイズが分からない場合がある。
チャンク連鎖による成長可能Arenaが必要。

GrowableArena
│
│  内部: Array[Arena]  — チャンクのリスト
│        mut current: Int  — 現在のチャンクインデックス
│
│  alloc():
│    current_chunk.alloc() が None なら:
│      新しいArenaチャンクを作成してリストに追加
│      current += 1
│      新チャンクで alloc()
│
│  Refの拡張:
│    GrowableRef = { chunk_index: Int, ref: Ref }
│    または上位ビットにchunk_indexをエンコード
│
│  reset():
│    全チャンクをreset()
│    current = 0
│
│  トレードオフ:
│    - 参照に1フィールド追加 (chunk_index)
│    - アクセス時にチャンクの間接参照が1段増える
│    - DSPでは固定Arenaで十分（バッファサイズは既知）
│    - パーサーやCRDT向け
│
│  実装優先度: 低（まず固定Arenaで始め、必要になったら追加）
```

---

## 10. 実装ロードマップ

```
Phase 1: 最小実装 (目標: 動くプロトタイプ)
├── MbBump (FixedArray[Byte]ベース)
├── MbGenStore (Array[Int]ベース)
├── Arena (固定スロット)
├── Ref
└── テスト: alloc, get, reset, stale ref検出

Phase 2: C-FFIバックエンド追加 (実装済み)
├── c_bump.c + CFFIBump                          ✓
├── c_gen.c + CGenStore                           ✓
├── Arena[B, G] ジェネリック型パラメータ方式      ✓ (enum dispatchではなくモノモーフィゼーション)
├── Arena::new / Arena::new_with / cffi.new_arena ✓
└── ベンチマーク: MbBump vs CFFIBump              ✓
    結果 (native, 1000 ops/iteration):
      Bump alloc: MbBump ~7 µs, CFFIBump ~8 µs (同等)
      Arena allocサイクル: 両方 ~12 µs (ディスパッチオーバーヘッドなし確認)
      reset単体 (空Arena): ~0 µs 近傍
      reset+再確保サイクル: 100 alloc と 10000 alloc で差が出る

Phase 3: 型付きArena
├── Storable trait
├── Double, Int の Storable実装
├── AudioFrame等のドメイン型 Storable実装
├── TypedRef[T]（パターンAの手動特殊化）
└── テスト: 型安全性 + アロケータ契約準拠の検証

Phase 4: ドメイン統合
├── AudioBufferPool (DSP)
├── ASTArena (パーサー)
├── incr generation連動
└── プロファイリング + Level 0 最適化

Phase 5: 拡張 (必要に応じて)
├── GrowableArena
├── コード生成によるTypedArena自動化
├── メモリ使用量の統計/可視化
└── Deterministic Simulation Testing統合
```

---

## 付録A: 型・関数の一覧表

| 名前 | 層 | 種類 | 役割 |
|------|-----|------|------|
| `BumpAllocator` | L1 | trait | 物理バイト列の割り当て/リセットの抽象 |
| `MbBump` | L1 | struct | FixedArray[Byte]ベースのbump allocator |
| `CFFIBump` | L1 | struct | C malloc/mmapベースのbump allocator |
| `GenStore` | L2 | trait | スロット世代管理の抽象 |
| `MbGenStore` | L2 | struct | Array[Int]ベースの世代ストレージ |
| `CGenStore` | L2 | struct | C int配列ベースの世代ストレージ |
| `Ref` | L2 | struct | generational index (index + generation) |
| `Arena` | L2 | struct | スロットベースのアロケータ本体 |
| `Storable` | L3 | trait | Arena上にバイト列として格納可能な型 |
| `TypedRef[T]` | L3 | struct | 型付きのArena参照 |
| `TypedArena[T]` | L3 | struct | 型Tに特化したArena |
| `BumpImpl` | 構成 | enum | BumpAllocator実装の切り替え |
| `GenStoreImpl` | 構成 | enum | GenStore実装の切り替え |
| `AudioBufferPool` | ドメイン | struct | DSP用バッファプール |
| `ASTArena` | ドメイン | struct | パーサー用ASTノードアリーナ |
| `GrowableArena` | 拡張 | struct | チャンク連鎖の成長可能Arena |

## 付録B: 意味論の形式的まとめ

```
定義:
  Arena = (bump: Bump, gen: GenStore, G: Int, count: Int, slot_size: Int)
  Ref   = (index: Int, generation: Int)

有効性:
  valid(r: Ref, a: Arena) ⟺
    r.index < a.count ∧
    r.generation == a.G ∧
    a.gen.get(r.index) == r.generation

割り当て:
  alloc(a: Arena) =
    let i = a.count
    a.bump.alloc(a.slot_size, align)
    a.gen.set(i, a.G)
    a.count += 1
    return Ref(i, a.G)

  事後条件: valid(returned_ref, a)

リセット:
  reset(a: Arena) =
    a.bump.reset()
    a.G += 1
    a.count = 0

  事後条件: ∀r. ¬valid(r, a)
    （全ての既存Refが無効化される）

読み出し:
  read(a: Arena, r: Ref) =
    if valid(r, a) then
      Some(a.bump.read(r.index * a.slot_size))
    else
      None

型付き:
  TypedRef[T] = Ref  (phantom type)
  alloc_typed[T: Storable](a: Arena, v: T) =
    let r = alloc(a)
    v.write_to(a.bump, r.index * a.slot_size)
    return TypedRef[T](r)
```
