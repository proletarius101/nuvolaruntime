/*
 * Copyright 2014 Jiří Janoušek <janousek.jiri@gmail.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met: 
 * 
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer. 
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution. 
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

public class Nuvola.LauncherBinding: ModelBinding<LauncherModel>
{
	public LauncherBinding(Drt.ApiRouter server, WebWorker web_worker, LauncherModel? model=null)
	{
		base(server, web_worker, "Nuvola.Launcher", model ?? new LauncherModel());
	}
	
	protected override void bind_methods()
	{
		bind("setTooltip", "(s)", handle_set_tooltip);
		bind("setActions", "(av)", handle_set_actions);
		bind("addAction", "(s)", handle_add_action);
		bind("removeAction", "(s)", handle_remove_action);
		bind("removeActions", null, handle_remove_actions);
	}
	
	private Variant? handle_set_tooltip(GLib.Object source, Variant? data) throws Diorite.MessageError
	{
		string text;
		data.get("(s)", out text);
		model.tooltip = text;
		return null;
	}
	
	private Variant? handle_add_action(GLib.Object source, Variant? data) throws Diorite.MessageError
	{
		string name;
		data.get("(s)", out name);
		model.add_action(name);
		return null;
	}
	
	private Variant? handle_remove_action(GLib.Object source, Variant? data) throws Diorite.MessageError
	{
		string name;
		data.get("(s)", out name);
		model.remove_action(name);
		return null;
	}
	
	private Variant? handle_set_actions(GLib.Object source, Variant? data) throws Diorite.MessageError
	{
		VariantIter iter = null;
		data.get("(av)", &iter);
		SList<string> actions = null;
		Variant item = null;
		while (iter.next("v", &item))
			actions.prepend(item.get_string());
		actions.reverse();
		model.actions = (owned) actions;
		return null;
	}
	
	private Variant? handle_remove_actions(GLib.Object source, Variant? data) throws Diorite.MessageError
	{
		model.remove_actions();
		return null;
	}
}
