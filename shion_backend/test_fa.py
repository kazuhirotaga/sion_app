import traceback
try:
    from financial_analyst import run_analysis_cycle
    import asyncio

    async def main():
        await run_analysis_cycle()

    if __name__ == "__main__":
        asyncio.run(main())
except Exception as e:
    with open("import_error.txt", "w", encoding="utf-8") as f:
        traceback.print_exc(file=f)
