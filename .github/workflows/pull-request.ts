name: Pull Request

on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]

concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.run_id }}
  cancel-in-progress: true

jobs:
  # Check if files in the /test, /crates, or /lib directories or the
  # /Cargo.lock, or /Cargo.toml files were changed in this PR.
  detect-changes:
    uses: ./.github/workflows/check-diff.yml
    with:
      pattern: ^test/\|^crates/\|^lib/\|^target/\|^Cargo\.lock$\|^Cargo\.toml$\|^\.github/workflows/rust_test\.yml$

  verify:
    runs-on: ubuntu-latest
    needs: detect-changes
    if: needs.detect-changes.outputs.changed == 'true'
    strategy:
      matrix:
        task: [lint, test]

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          submodules: recursive
          token: ${{ secrets.GITHUB_TOKEN }}

      - uses: actions-rs/toolchain@v1
        with:
          toolchain: nightly
          override: true
          components: rustfmt, clippy


      - name: Run ${{ matrix.task }}
         run: make ${{ matrix.task }}
