# Fix text selection in Code Composer Studio on macOS

When you select text in Code Composer Studio (CCS), you can't see what you selected. This page fixes that.

It happens in CCS versions built on Eclipse, like CCS 12, on macOS 26.1 or newer. Deep inside CCS, one number is too big for the new macOS. This fix changes that one number. CCS 20 and newer is built differently and doesn't need it.

There are two ways to fix it. Pick one:

- **[Automatic fix](#automatic-fix):** paste one line. It takes 1 minute. Start here!
- **[Manual fix](#manual-fix):** do every step yourself. It takes 5 minutes.

The change comes from the official fix, [eclipse.platform.swt #2694](https://github.com/eclipse-platform/eclipse.platform.swt/pull/2694). The first Eclipse that has it needs a newer Java than CCS has, so we put the same change into the file CCS already has.

---

## Automatic fix

### Do these steps

1. Close Code Composer Studio.
2. Open the **Terminal** app: press <kbd>Command</kbd> + <kbd>Space</kbd>, type `Terminal` and press <kbd>Enter</kbd>.
3. Copy this line, paste it into Terminal and press <kbd>Enter</kbd>:

   ```bash
   curl -fsSL https://gitlab.rub.de/artem.h/ccs-selection-fix/-/raw/main/fix-ccs-selection.sh | bash
   ```

4. Wait until you see **Fixed!** or **All good!**
5. Open Code Composer Studio again. Select some text. You can see it now! 🎉

### If it asks for your password

Type your Mac password and press <kbd>Enter</kbd>. The letters stay invisible while you type. That is normal!

### If something goes wrong

You can't break anything. If you are not sure, just paste the line again.

| What happened | What to do |
| --- | --- |
| I stopped it, closed the window, or the Mac turned off. | That's okay. Paste the line again. It finishes the job. |
| I did it twice. | That's okay. It will say **All good!** |
| I see red text. | Read the red line. It tells you what to do. Then paste the line again. |
| It says **CCS is still open**. | Close Code Composer Studio and open it again. |
| It says **This copy of me got damaged**. | The download broke. CCS was not touched. Paste the line again. |
| It says **curl:** and an error. | Check your internet. Then paste the line again. |
| It says **syntax error**. | This page is not open to everyone yet. CCS was not touched. Tell the person who sent you this link. |
| It says **I could not find Code Composer Studio**. | Use the steps under [Fix with the file](#fix-with-the-file). Before you press <kbd>Enter</kbd>, press <kbd>Space</kbd> and drag your CCS folder into the Terminal window too. |
| The bug came back after I reinstalled CCS. | That's normal. Paste the line again. |

### Undo the fix

Close Code Composer Studio. Paste this line into Terminal and press <kbd>Enter</kbd>:

```bash
curl -fsSL https://gitlab.rub.de/artem.h/ccs-selection-fix/-/raw/main/fix-ccs-selection.sh | bash -s -- undo
```

### Fix with the file

Use this if the line above doesn't work for you.

1. Close Code Composer Studio.
2. Download the file [fix-ccs-selection.sh](fix-ccs-selection.sh).
3. Open the **Terminal** app.
4. Type the word `bash`, then press <kbd>Space</kbd> once. Don't press <kbd>Enter</kbd> yet.
5. Drag the file you downloaded into the Terminal window and let go.
6. Press <kbd>Enter</kbd>. If a box asks to allow Terminal to use a folder, click **Allow**.
7. Wait until you see **Fixed!** or **All good!** Then open Code Composer Studio.

To undo, do steps 1 to 5. Then press <kbd>Space</kbd>, type `undo` and press <kbd>Enter</kbd>.

Don't paste the file into a text editor. That can damage it. If it happens, the file will tell you and stop.

---

## Manual fix

We will take one file out of CCS, change the wrong number, and put the file back.

### Good to know

- You only need the Terminal app. You don't need to install anything.
- Copy **one** box. Paste it into Terminal. Press <kbd>Enter</kbd>. Then do the next box.
- Keep the same Terminal window open until you finish.
- CCS does not change until step 9. Before that, you can stop any time.
- Lost? Start again from step 1. That is safe.

### Do these steps

**Step 1.** Close Code Composer Studio.

**Step 2.** Open the **Terminal** app: press <kbd>Command</kbd> + <kbd>Space</kbd>, type `Terminal` and press <kbd>Enter</kbd>.

**Step 3.** Find your CCS. Paste these 3 boxes, one at a time:

```bash
P=/Applications/ti/ccs1281/ccs/eclipse/Eclipse.app/Contents/Eclipse/plugins
```

```bash
JAR=$(echo $P/org.eclipse.swt.cocoa.macosx.*.jar)
```

```bash
echo $JAR
```

You should see one long line that ends with `.jar`.

Do you see `no matches found` instead? Your CCS has a different name. Open the folder `/Applications/ti` and find the folder that looks like `ccs1281`. Change `ccs1281` in the first box to that name, then do this step again.

**Step 4.** Make a work folder on your Desktop:

```bash
mkdir -p ~/Desktop/ccs-fix
```

```bash
cd ~/Desktop/ccs-fix
```

**Step 5.** Make a safety copy, and a copy to work on:

```bash
cp -n "$JAR" .
```

```bash
cp -f "$JAR" fixed.jar
```

You should see nothing. That is good!

**Step 6.** Take out the file with the wrong number:

```bash
unzip -o fixed.jar org/eclipse/swt/graphics/TextLayout.class
```

You should see the word `inflating`.

**Step 7.** Change the number, then check it:

```bash
perl -0777 -pi -e 's/\x06\x41\xdf\xff\xff\xff\xc0\x00\x00/\x06\x41\x53\x12\xd0\x00\x00\x00\x00/' org/eclipse/swt/graphics/TextLayout.class
```

```bash
unzip -p fixed.jar org/eclipse/swt/graphics/TextLayout.class | cmp -l - org/eclipse/swt/graphics/TextLayout.class | wc -l
```

You should see the number `5`.

- You see `0`? Your CCS was already fixed. You are done!
- You see another number? Stop. Nothing changed. Start again from step 1.

**Step 8.** Put the file back, take off the old seal, and check it. The seal only fits the old file, so it has to go.

```bash
zip fixed.jar org/eclipse/swt/graphics/TextLayout.class
```

```bash
zip -d fixed.jar META-INF/ECLIPSE_.SF META-INF/ECLIPSE_.RSA
```

```bash
unzip -tq fixed.jar
```

You might see a line that says `zip warning`. That is okay! At the very end you should see `No errors detected`.

**Step 9.** Put the fixed file into CCS. This is the only step that changes CCS:

```bash
cp fixed.jar "$JAR.new" && mv -f "$JAR.new" "$JAR"
```

You should see nothing. That is good!

Do you see `Permission denied`? Paste this box instead. Type your Mac password and press <kbd>Enter</kbd>. The letters stay invisible while you type. That is normal!

```bash
sudo cp fixed.jar "$JAR.new" && sudo mv -f "$JAR.new" "$JAR"
```

**Step 10.** Open Code Composer Studio. Select some text. You can see it now! 🎉

Keep the `ccs-fix` folder on your Desktop for a few days. It has your safety copy inside. When CCS works well, drag the folder to the Trash.

### Undo the manual fix

CCS won't open, or you want it back how it was? Close Code Composer Studio. Paste this box into Terminal and press <kbd>Enter</kbd>. If you changed `ccs1281` in step 3, change it here too.

```bash
cp ~/Desktop/ccs-fix/org.eclipse.swt.cocoa.macosx.*.jar /Applications/ti/ccs1281/ccs/eclipse/Eclipse.app/Contents/Eclipse/plugins/
```

### The bug came back?

That happens if you reinstall CCS. Do all the steps again.
