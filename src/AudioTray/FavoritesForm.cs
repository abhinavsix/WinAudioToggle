using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace AudioTray
{
    /// <summary>
    /// Picks which outputs left-clicking cycles through, in what order, and
    /// what each one looks like in the tray.
    /// </summary>
    internal sealed class FavoritesForm : Form
    {
        sealed class Row
        {
            public string Name = "";
            public bool Favorite;
            public string IconPath = "";
        }

        readonly List<Row> _rows = new List<Row>();
        readonly ListView _list = new ListView();
        readonly ImageList _icons = new ImageList();

        public FavoritesForm(AudioDevice[] outputs)
        {
            BuildLayout();
            Populate(outputs);
        }

        void BuildLayout()
        {
            Text = AppInfo.Title + " - favourite outputs";
            FormBorderStyle = FormBorderStyle.Sizable;
            StartPosition = FormStartPosition.CenterScreen;
            MinimizeBox = false;
            MaximizeBox = false;
            ShowInTaskbar = true;
            ClientSize = new Size(600, 400);
            MinimumSize = new Size(500, 320);
            Icon = IconFactory.Microphone(false);

            Label hint = new Label();
            hint.Text = "Tick the outputs you want to cycle through with a left click. "
                      + "Use Move up and Move down to set the order, and give each one an icon "
                      + "so you can tell them apart in the tray.";
            hint.Dock = DockStyle.Top;
            hint.Height = 46;
            hint.Padding = new Padding(10, 8, 10, 0);

            _icons.ImageSize = new Size(16, 16);
            _icons.ColorDepth = ColorDepth.Depth32Bit;

            _list.Dock = DockStyle.Fill;
            _list.View = View.Details;
            _list.CheckBoxes = true;
            _list.FullRowSelect = true;
            _list.MultiSelect = false;
            _list.HideSelection = false;
            _list.SmallImageList = _icons;
            _list.Columns.Add("Output device", 330);
            _list.Columns.Add("Icon", 210);
            _list.ItemChecked += OnItemChecked;

            Panel buttons = new Panel();
            buttons.Dock = DockStyle.Bottom;
            buttons.Height = 92;

            AddButton(buttons, "Choose icon...", 10, delegate { ChooseIcon(); });
            AddButton(buttons, "Clear icon", 130, delegate { ClearIcon(); });
            AddButton(buttons, "Move up", 250, delegate { MoveSelection(-1); });
            AddButton(buttons, "Move down", 340, delegate { MoveSelection(1); });

            Button ok = AddButton(buttons, "Save", 10, delegate { Persist(); }, 50);
            ok.DialogResult = DialogResult.OK;

            Button cancel = AddButton(buttons, "Cancel", 100, null, 50);
            cancel.DialogResult = DialogResult.Cancel;

            Label where = new Label();
            where.Text = "Saved to " + Favorites.FilePath;
            where.AutoSize = false;
            where.SetBounds(200, 56, 380, 30);
            where.ForeColor = SystemColors.GrayText;
            buttons.Controls.Add(where);

            AcceptButton = ok;
            CancelButton = cancel;

            Controls.Add(_list);
            Controls.Add(hint);
            Controls.Add(buttons);
        }

        Button AddButton(Control parent, string text, int x, EventHandler onClick, int y = 10)
        {
            Button button = new Button();
            button.Text = text;
            button.SetBounds(x, y, text.Length > 10 ? 110 : 80, 30);
            if (onClick != null) { button.Click += onClick; }
            parent.Controls.Add(button);
            return button;
        }

        void Populate(AudioDevice[] outputs)
        {
            List<FavoriteEntry> saved = Favorites.Load();

            // Saved favourites first, in their stored order, so the list reads
            // as the cycle order it actually is.
            foreach (FavoriteEntry entry in saved)
            {
                foreach (AudioDevice device in outputs)
                {
                    bool alreadyListed = _rows.Exists(delegate(Row r) { return r.Name == device.Name; });
                    if (entry.Matches(device) && !alreadyListed)
                    {
                        _rows.Add(new Row { Name = device.Name, Favorite = true, IconPath = entry.IconPath });
                        break;
                    }
                }
            }

            List<AudioDevice> remaining = new List<AudioDevice>(outputs);
            remaining.Sort(delegate(AudioDevice a, AudioDevice b)
            {
                return string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase);
            });

            foreach (AudioDevice device in remaining)
            {
                bool alreadyListed = _rows.Exists(delegate(Row r) { return r.Name == device.Name; });
                if (!alreadyListed)
                {
                    _rows.Add(new Row { Name = device.Name, Favorite = false, IconPath = "" });
                }
            }

            Rebuild();
        }

        void Rebuild()
        {
            int selected = _list.SelectedIndices.Count > 0 ? _list.SelectedIndices[0] : -1;

            _list.BeginUpdate();
            _list.ItemChecked -= OnItemChecked;
            _list.Items.Clear();
            _icons.Images.Clear();

            for (int i = 0; i < _rows.Count; i++)
            {
                Row row = _rows[i];

                Icon preview = IconFactory.Output(row.Name, row.IconPath);
                _icons.Images.Add(preview.ToBitmap());

                ListViewItem item = new ListViewItem(row.Name);
                item.Checked = row.Favorite;
                item.ImageIndex = i;
                item.SubItems.Add(row.IconPath.Length > 0
                                  ? Path.GetFileName(row.IconPath)
                                  : "(automatic)");
                _list.Items.Add(item);
            }

            _list.ItemChecked += OnItemChecked;
            _list.EndUpdate();

            if (selected >= 0 && selected < _list.Items.Count)
            {
                _list.Items[selected].Selected = true;
                _list.Items[selected].Focused = true;
            }
        }

        void OnItemChecked(object sender, ItemCheckedEventArgs e)
        {
            if (e.Item.Index >= 0 && e.Item.Index < _rows.Count)
            {
                _rows[e.Item.Index].Favorite = e.Item.Checked;
            }
        }

        int SelectedIndex
        {
            get { return _list.SelectedIndices.Count > 0 ? _list.SelectedIndices[0] : -1; }
        }

        void ChooseIcon()
        {
            int index = SelectedIndex;
            if (index < 0) { Warn("Select a device first."); return; }

            using (OpenFileDialog dialog = new OpenFileDialog())
            {
                dialog.Title = "Choose an icon for " + _rows[index].Name;
                dialog.Filter = "Icons and images|*.ico;*.png;*.bmp;*.jpg;*.jpeg;*.gif|"
                              + "Icons|*.ico|Images|*.png;*.bmp;*.jpg;*.jpeg;*.gif|All files|*.*";
                dialog.CheckFileExists = true;

                if (dialog.ShowDialog(this) != DialogResult.OK) { return; }

                _rows[index].IconPath = dialog.FileName;
                if (!_rows[index].Favorite)
                {
                    // Choosing an icon plainly means "I want this one".
                    _rows[index].Favorite = true;
                }

                IconFactory.Invalidate();
                Rebuild();
            }
        }

        void ClearIcon()
        {
            int index = SelectedIndex;
            if (index < 0) { Warn("Select a device first."); return; }

            _rows[index].IconPath = "";
            IconFactory.Invalidate();
            Rebuild();
        }

        void MoveSelection(int direction)
        {
            int index = SelectedIndex;
            if (index < 0) { Warn("Select a device first."); return; }

            int target = index + direction;
            if (target < 0 || target >= _rows.Count) { return; }

            Row moved = _rows[index];
            _rows[index] = _rows[target];
            _rows[target] = moved;

            Rebuild();
            _list.Items[target].Selected = true;
            _list.Items[target].Focused = true;
            _list.EnsureVisible(target);
        }

        void Persist()
        {
            List<FavoriteEntry> entries = new List<FavoriteEntry>();
            foreach (Row row in _rows)
            {
                if (!row.Favorite) { continue; }
                entries.Add(new FavoriteEntry { Pattern = row.Name, IconPath = row.IconPath });
            }

            if (entries.Count == 1)
            {
                Warn("Only one favourite is ticked, so there would be nothing to cycle to. "
                     + "Tick a second one, or untick it to cycle through every device.");
            }

            string failure = Favorites.Save(entries);
            if (failure != null)
            {
                Warn("Could not save: " + failure);
                DialogResult = DialogResult.None;
                return;
            }

            IconFactory.Invalidate();
        }

        void Warn(string message)
        {
            MessageBox.Show(this, message, AppInfo.Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }
}
